#!/usr/bin/env bash
set -euo pipefail

# Repo HashiCorp + paquete consul
if ! command -v consul >/dev/null 2>&1; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y consul
fi

# Asegurar unit (algunos paquetes ya la traen, pero preferimos nuestra línea de arranque)
sudo tee /etc/systemd/system/consul.service >/dev/null <<'UNIT'
[Unit]
Description=HashiCorp Consul - Agent
Documentation=https://www.consul.io/
Requires=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
TimeoutStartSec=120
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable consul
