#!/usr/bin/env bash
set -euo pipefail

sudo apt-get update -y
sudo apt-get install -y curl unzip jq gnupg lsb-release apt-transport-https dos2unix

# Normalizar fin de línea de TODOS los scripts de provision y plantillas
if [ -d /vagrant/provision ]; then
  sudo find /vagrant/provision -type f -name "*.sh" -exec sudo dos2unix {} \; || true
fi

# Usuario y directorios Consul
if ! id consul >/dev/null 2>&1; then
  sudo useradd --system --home /etc/consul.d --shell /usr/sbin/nologin consul
fi
sudo mkdir -p /etc/consul.d /var/lib/consul /opt/consul
sudo chown -R consul:consul /etc/consul.d /var/lib/consul /opt/consul
sudo chmod 750 /etc/consul.d
