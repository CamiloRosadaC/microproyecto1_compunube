#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log() { echo "[web] $*"; }

# --- Auto-elevación si no es root ---
if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

# --- Vars con defaults sensatos ---
CONSUL_SERVER_IP="${CONSUL_SERVER_IP:-192.168.100.2}"
CONSUL_DATACENTER="${CONSUL_DATACENTER:-dc1}"
SERVICE_NAME="${SERVICE_NAME:-web}"
REPLICAS="${REPLICAS:-2}"
PORTS_CSV="${PORTS:-3000,3001}"
HEALTH_PATH="${HEALTH_PATH:-/health}"

# IP local (inyectada por common.sh si existe)
source /etc/profile.d/microproyecto.sh 2>/dev/null || true
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

# --- Paquetes base necesarios ---
log "apt update + utilidades mínimas"
apt-get -o Acquire::Retries=3 update -y
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release

# --- Instalar Consul (si falta) ---
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

# --- Config cliente Consul ---
install -d -m 0755 -o consul -g consul /etc/consul.d /opt/consul
cat >/etc/consul.d/client.hcl <<EOF
datacenter     = "${CONSUL_DATACENTER}"
node_name      = "$(hostname)"
server         = false
data_dir       = "/opt/consul"
bind_addr      = "${PRIVATE_IP}"
advertise_addr = "${PRIVATE_IP}"
client_addr    = "0.0.0.0"
retry_join     = ["${CONSUL_SERVER_IP}"]
EOF
chown -R consul:consul /etc/consul.d /opt/consul

# --- Unit systemd para Consul (simple y robusta) ---
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

# --- Node.js (HTTP nativo; sin Express) ---
# En Ubuntu recientes, 'nodejs' provee /usr/bin/node. Si no, creamos symlink.
log "instalando Node.js (paquete distro)"
apt-get install -y --no-install-recommends nodejs
if ! command -v node >/dev/null 2>&1 && command -v nodejs >/dev/null 2>&1; then
  ln -sf "$(command -v nodejs)" /usr/bin/node
fi

# --- App mínima con / y /health ---
install -d -m 0755 /opt/webapp
cat >/opt/webapp/server.js <<'EOF'
const http = require('http');
const os = require('os');
const port = process.env.PORT || 3000;
const healthPath = process.env.HEALTH_PATH || '/health';

const srv = http.createServer((req, res) => {
  if (req.url === healthPath) {
    res.writeHead(200, {'Content-Type': 'text/plain'});
    return res.end('OK');
  }
  res.writeHead(200, {'Content-Type': 'text/plain'});
  res.end(`Hola desde ${os.hostname()} en el puerto ${port}\n`);
});

srv.listen(port, '0.0.0.0', () => console.log(`Server up on ${port}`));
EOF

# --- Servicio systemd parametrizado (web@PUERTO) ---
cat >/etc/systemd/system/web@.service <<'EOF'
[Unit]
Description=Web demo (%i)
After=network.target

[Service]
Environment=PORT=%i
Environment=HEALTH_PATH=/health
WorkingDirectory=/opt/webapp
ExecStart=/usr/bin/node /opt/webapp/server.js
Restart=always
RestartSec=2
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

# --- Parseo de puertos + tope por REPLICAS ---
IFS=',' read -r -a PORTS <<<"${PORTS_CSV}"
clean_ports=()
for p in "${PORTS[@]}"; do
  p_trim="$(echo "${p}" | xargs)"
  [[ -n "${p_trim}" ]] && clean_ports+=("${p_trim}")
done

if (( ${#clean_ports[@]} == 0 )); then
  log "ERROR: PORTS está vacío tras el saneo."
  exit 1
fi

# --- Lanzar y registrar hasta REPLICAS ---
started=0
for p in "${clean_ports[@]}"; do
  (( started >= REPLICAS )) && break

  # Arranca servicio web@PUERTO
  systemctl enable --now "web@${p}"

  # Registro dinámico en Consul
  cat >/etc/consul.d/${SERVICE_NAME}-${p}.json <<EOF
{
  "service": {
    "name": "${SERVICE_NAME}",
    "id": "${SERVICE_NAME}-$(hostname)-${p}",
    "address": "${PRIVATE_IP}",
    "port": ${p},
    "checks": [
      {
        "http": "http://${PRIVATE_IP}:${p}${HEALTH_PATH}",
        "interval": "5s",
        "timeout": "2s"
      }
    ]
  }
}
EOF

  started=$((started+1))
done

# Validación y recarga de Consul
consul validate /etc/consul.d && consul reload || systemctl restart consul

# --- Pruebas rápidas locales (best-effort) ---
for p in "${clean_ports[@]:0:${REPLICAS}}"; do
  curl -fsS "http://127.0.0.1:${p}${HEALTH_PATH}" >/dev/null || true
done

log "lanzadas ${started}/${REPLICAS} réplicas en puertos: ${clean_ports[*]}"
log "node: $(node -v 2>/dev/null || echo 'desconocida')"
log "Consul servicios (filtro ${SERVICE_NAME}):"
consul catalog services 2>/dev/null | grep -E "^${SERVICE_NAME}$" || true
