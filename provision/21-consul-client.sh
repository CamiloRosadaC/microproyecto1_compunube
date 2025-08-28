#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${1:-}"
if [ -z "$SERVER_IP" ]; then
  echo "ERROR: Debes pasar la IP del Consul server como primer argumento (e.g., 192.168.100.10)"
  exit 1
fi

# Detectar la IP de la red 192.168.100.0/24 (la interfaz "host-only" de Vagrant)
LOCAL_IP="$(ip -4 -o addr show | awk '/192\.168\.100\./ {print $4}' | cut -d/ -f1 | head -n1)"
if [ -z "$LOCAL_IP" ]; then
  echo "ERROR: No se encontró IP en 192.168.100.0/24. Revisa tu red privada de Vagrant."
  ip -4 -o addr show || true
  exit 1
fi

sudo mkdir -p /etc/consul.d
sudo tee /etc/consul.d/client.hcl >/dev/null <<EOF
server           = false
datacenter       = "dc1"
node_name        = "$(hostname)"
data_dir         = "/var/lib/consul"

bind_addr        = "${LOCAL_IP}"
advertise_addr   = "${LOCAL_IP}"
client_addr      = "0.0.0.0"

retry_join       = ["${SERVER_IP}"]
log_level        = "INFO"
EOF

sudo chown -R consul:consul /etc/consul.d /var/lib/consul
sudo chmod 640 /etc/consul.d/*.hcl
sudo find /etc/consul.d -type d -exec sudo chmod 750 {} \;

# Validar y arrancar
sudo consul validate /etc/consul.d
sudo systemctl restart consul
sudo systemctl status --no-pager consul || true

