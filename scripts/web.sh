#!/usr/bin/env bash
set -euo pipefail

CONSUL_SERVER_IP="${CONSUL_SERVER_IP:-192.168.100.2}"
SERVICE_NAME="${SERVICE_NAME:-web}"
REPLICAS="${REPLICAS:-2}"
PORTS_CSV="${PORTS:-3000,3001}"

source /etc/profile.d/microproyecto.sh || true
PRIVATE_IP="${PRIVATE_IP:-$(hostname -I | awk '{print $1}')}"

# --- Instalar Consul ---
if ! command -v consul >/dev/null 2>&1; then
  install -o root -g root -m 0755 -d /usr/share/keyrings
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    >/etc/apt/sources.list.d/hashicorp.list
  apt-get update -y
  apt-get install -y consul
fi

install -d -m 0755 -o consul -g consul /etc/consul.d /opt/consul
cat >/etc/consul.d/client.hcl <<EOF
datacenter = "dc1"
node_name  = "$(hostname)"
server     = false
data_dir   = "/opt/consul"
bind_addr  = "${PRIVATE_IP}"
advertise_addr = "${PRIVATE_IP}"
client_addr = "0.0.0.0"
retry_join = ["${CONSUL_SERVER_IP}"]
EOF
chown -R consul:consul /etc/consul.d /opt/consul

# --- Systemd para Consul (Type=simple) ---
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

# --- Instalar Node.js (sin Express; usaremos http nativo) ---
apt-get install -y nodejs

# --- App simple /health y "/" ---
install -d -m 0755 /opt/webapp
cat >/opt/webapp/server.js <<'EOF'
const http = require('http');
const os = require('os');
const port = process.env.PORT || 3000;

const srv = http.createServer((req, res) => {
  if (req.url === '/health') {
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

# --- Arrancar réplicas y registrarlas en Consul ---
IFS=',' read -r -a PORTS <<< "${PORTS_CSV}"
count=0
for p in "${PORTS[@]}"; do
  [[ $count -ge ${REPLICAS} ]] && break
  systemctl enable --now "web@${p}"

  cat >/etc/consul.d/${SERVICE_NAME}-${p}.json <<EOF
{
  "service": {
    "name": "${SERVICE_NAME}",
    "id": "${SERVICE_NAME}-$(hostname)-${p}",
    "address": "${PRIVATE_IP}",
    "port": ${p},
    "checks": [
      {
        "http": "http://${PRIVATE_IP}:${p}/health",
        "interval": "5s",
        "timeout": "2s"
      }
    ]
  }
}
EOF
  count=$((count+1))
done

consul validate /etc/consul.d && consul reload || systemctl restart consul

# Pruebas locales
for p in "${PORTS[@]}"; do curl -s "http://127.0.0.1:${p}/health" || true; done
