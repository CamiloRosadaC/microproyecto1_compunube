#!/usr/bin/env bash
set -euo pipefail

CONSUL_SERVER_IP="${CONSUL_SERVER_IP:-192.168.100.2}"
SERVICE_NAME="${SERVICE_NAME:-web}"
PORTS="${PORTS:-3000,3001}"

source /etc/profile.d/microproyecto.sh || true

# --- Instalar Consul (repo oficial) ---
if ! command -v consul >/dev/null 2>&1; then
  install -o root -g root -m 0755 -d /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    >/etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  apt-get install -y consul
fi

# --- Configuración Consul: servidor de 1 nodo ---
install -d -m 0755 -o consul -g consul /etc/consul.d /opt/consul
BIND_IP="${PRIVATE_IP:-${CONSUL_SERVER_IP}}"
cat >/etc/consul.d/server.hcl <<EOF
datacenter = "dc1"
node_name  = "haproxy"
server     = true
bootstrap_expect = 1
data_dir   = "/opt/consul"
bind_addr  = "${BIND_IP}"
advertise_addr = "${BIND_IP}"
client_addr = "0.0.0.0"
EOF
chown -R consul:consul /etc/consul.d /opt/consul

# --- Systemd para Consul (Type=simple para evitar timeouts) ---
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

# --- Instalar HAProxy ---
apt-get install -y haproxy

# Página 503 personalizada
cat >/etc/haproxy/errors/503-custom.http <<'EOF'
HTTP/1.1 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>Ups…</h1><p>En este momento no hay servidores disponibles. Por favor intenta más tarde.</p></body></html>
EOF

# Config HAProxy con discovery via Consul DNS (SRV)
cat >/etc/haproxy/haproxy.cfg <<'EOF'
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
    option  httpchk GET /health
    default-server init-addr last,libc,none

resolvers consul
    nameserver dns1 127.0.0.1:8600
    resolve_retries       30
    timeout resolve       5s
    hold valid            10s
    accepted_payload_size 8192

frontend fe_http
    bind *:80
    default_backend be_web
    stats enable
    stats uri /haproxy?stats
    stats refresh 2s

backend be_web
    balance roundrobin
    http-check expect status 200
    # Permite múltiples instancias en la MISMA IP (puertos distintos)
    server-template web 10 _web._tcp.service.consul resolvers consul \
        resolve-prefer ipv4 resolve-opts allow-dup-ip \
        check inter 2s fall 2 rise 1

    errorfile 503 /etc/haproxy/errors/503-custom.http
EOF

systemctl enable haproxy
systemctl restart haproxy

echo "[haproxy] GUI: http://${BIND_IP}/haproxy?stats"
