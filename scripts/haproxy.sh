#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() { echo "[haproxy] $*"; }

# Auto-elevación si no es root
if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

# --- Variables de entorno (con defaults sensatos) ---
# Descubrimiento: consul | static
DISCOVERY_MODE="${DISCOVERY_MODE:-consul}"

# Consul
CONSUL_SERVER_IP="${CONSUL_SERVER_IP:-192.168.100.2}"
SERVICE_NAME="${SERVICE_NAME:-web}"       # nombre lógico para SRV: _web._tcp.service.consul
CONSUL_DATACENTER="${CONSUL_DATACENTER:-dc1}"
CONSUL_NODE_NAME="${CONSUL_NODE_NAME:-haproxy}"
CONSUL_BOOTSTRAP_EXPECT="${CONSUL_BOOTSTRAP_EXPECT:-1}"

# HAProxy
STATS_URI="${STATS_URI:-/haproxy?stats}"
STATS_USER="${STATS_USER:-admin}"
STATS_PASS="${STATS_PASS:-admin}"
HTTPCHK_PATH="${HTTPCHK_PATH:-/}"         # /health si tus webs lo exponen
FRONTEND_PORT="${FRONTEND_PORT:-80}"

# Static backends (solo si DISCOVERY_MODE=static), ej:
# BACKENDS="192.168.100.11:80,192.168.100.12:80"
BACKENDS="${BACKENDS:-}"

# IP local descubierta por common.sh
source /etc/profile.d/microproyecto.sh 2>/dev/null || true
BIND_IP="${PRIVATE_IP:-${CONSUL_SERVER_IP}}"

# --- Paquetes requeridos ---
log "instalando/asegurando HAProxy"
apt-get -o Acquire::Retries=3 update -y
apt-get install -y --no-install-recommends haproxy

# --- Consul (solo si DISCOVERY_MODE=consul) ---
if [[ "${DISCOVERY_MODE}" == "consul" ]]; then
  if ! command -v consul >/dev/null 2>&1; then
    log "instalando Consul (repo oficial)"
    install -o root -g root -m 0755 -d /usr/share/keyrings
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      >/etc/apt/sources.list.d/hashicorp.list
    apt-get update -y
    apt-get install -y --no-install-recommends consul
  fi

  log "configurando Consul (modo servidor de 1 nodo)"
  install -d -m 0755 -o consul -g consul /etc/consul.d /opt/consul

  cat >/etc/consul.d/server.hcl <<EOF
datacenter    = "${CONSUL_DATACENTER}"
node_name     = "${CONSUL_NODE_NAME}"
server        = true
bootstrap_expect = ${CONSUL_BOOTSTRAP_EXPECT}
data_dir      = "/opt/consul"
bind_addr     = "${BIND_IP}"
advertise_addr= "${BIND_IP}"
client_addr   = "0.0.0.0"
EOF
  chown -R consul:consul /etc/consul.d /opt/consul

  # Unit systemd (simple y resistente a timeouts)
  cat >/etc/systemd/system/consul.service <<'EOF'
[Unit]
Description=HashiCorp Consul - agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d/
Restart=on-failure
RestartSec=2
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable consul
  systemctl restart consul
  sleep 1
  consul members || true
fi

# --- Página 503 personalizada ---
install -d /etc/haproxy/errors
cat >/etc/haproxy/errors/503-custom.http <<'EOF'
HTTP/1.1 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>Ups…</h1><p>En este momento no hay servidores disponibles. Por favor intenta más tarde.</p></body></html>
EOF

# --- Backup de configuración original (una sola vez) ---
if [[ ! -f /etc/haproxy/haproxy.cfg.bak ]]; then
  cp -a /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak || true
fi

# --- Generación dinámica de haproxy.cfg ---
log "generando /etc/haproxy/haproxy.cfg (modo: ${DISCOVERY_MODE})"

if [[ "${DISCOVERY_MODE}" == "consul" ]]; then
  # Config: resolvers -> DNS de Consul en localhost:8600 + server-template SRV
  cat >/etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    maxconn 4096
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout check   5s
    option  httpchk GET ${HTTPCHK_PATH}
    default-server init-addr last,libc,none

resolvers consul
    nameserver dns1 127.0.0.1:8600
    resolve_retries       30
    timeout resolve       5s
    hold valid            10s
    accepted_payload_size 8192

frontend fe_http
    bind *:${FRONTEND_PORT}
    default_backend be_web
    stats enable
    stats uri ${STATS_URI}
    stats refresh 2s
    stats auth ${STATS_USER}:${STATS_PASS}

backend be_web
    balance roundrobin
    http-check expect status 200
    # Hasta 10 instancias descubiertas por SRV: _${SERVICE_NAME}._tcp.service.consul
    server-template ${SERVICE_NAME} 10 _${SERVICE_NAME}._tcp.service.consul resolvers consul \\
        resolve-prefer ipv4 resolve-opts allow-dup-ip \\
        check inter 2s fall 2 rise 1
    errorfile 503 /etc/haproxy/errors/503-custom.http
EOF

else
  # Modo STATIC: requiere BACKENDS="IP:PUERTO,IP:PUERTO"
  if [[ -z "${BACKENDS// }" ]]; then
    log "ERROR: DISCOVERY_MODE=static pero BACKENDS está vacío."
    log "Ejemplo: BACKENDS=\"192.168.100.11:80,192.168.100.12:80\""
    exit 1
  fi

  # Construir líneas 'server' a partir de BACKENDS
  SERVER_LINES=""
  IFS=',' read -r -a arr <<<"${BACKENDS}"
  idx=1
  for be in "${arr[@]}"; do
    be_trim="$(echo "${be}" | xargs)"
    [[ -z "${be_trim}" ]] && continue
    SERVER_LINES+="    server web${idx} ${be_trim} check inter 2s fall 2 rise 1\n"
    idx=$((idx+1))
  done

  cat >/etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    maxconn 4096
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout check   5s
    option  httpchk GET ${HTTPCHK_PATH}

frontend fe_http
    bind *:${FRONTEND_PORT}
    default_backend be_web
    stats enable
    stats uri ${STATS_URI}
    stats refresh 2s
    stats auth ${STATS_USER}:${STATS_PASS}

backend be_web
    balance roundrobin
    http-check expect status 200
$(echo -e "${SERVER_LINES}")    errorfile 503 /etc/haproxy/errors/503-custom.http
EOF
fi

# --- Reinicio/enable ---
systemctl enable haproxy
systemctl restart haproxy

log "frontend: http://$(hostname -I | awk '{print $1}'):${FRONTEND_PORT}/"
log "stats:    http://$(hostname -I | awk '{print $1}'):${FRONTEND_PORT}${STATS_URI} (user: ${STATS_USER})"
log "modo:     ${DISCOVERY_MODE}"
