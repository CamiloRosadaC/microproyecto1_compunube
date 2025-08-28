#!/usr/bin/env bash
set -euo pipefail

# Detectar IP de la red privada de Vagrant
LOCAL_IP="$(ip -4 -o addr show | awk '/192\.168\.100\./ {print $4}' | cut -d/ -f1 | head -n1)"
if [ -z "$LOCAL_IP" ]; then
  echo "ERROR: No se encontró IP en 192.168.100.0/24. Revisa tu red privada."
  ip -4 -o addr show || true
  exit 1
fi

sudo mkdir -p /etc/consul.d
sudo tee /etc/consul.d/server.hcl >/dev/null <<EOF
server           = true
bootstrap_expect = 1
datacenter       = "dc1"
node_name        = "haproxy"
data_dir         = "/var/lib/consul"

bind_addr        = "${LOCAL_IP}"
advertise_addr   = "${LOCAL_IP}"
client_addr      = "0.0.0.0"

ui_config { enabled = true }
ports { dns = 8600 }

log_level = "INFO"
EOF

sudo chown -R consul:consul /etc/consul.d /var/lib/consul
sudo chmod 640 /etc/consul.d/*.hcl
sudo find /etc/consul.d -type d -exec sudo chmod 750 {} \;

sudo consul validate /etc/consul.d
sudo systemctl restart consul
sudo systemctl status --no-pager consul || true
