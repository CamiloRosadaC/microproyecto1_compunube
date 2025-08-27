#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl unzip jq ca-certificates gnupg lsb-release apt-transport-https \
                   dnsutils iproute2 net-tools

# Detecta IP privada 192.168.100.X (para logs o registros)
PRIVATE_IP="$(hostname -I | tr ' ' '\n' | grep -E '^192\.168\.100\.' | head -n1 || true)"
mkdir -p /etc/profile.d
cat >/etc/profile.d/microproyecto.sh <<EOF
export PRIVATE_IP="${PRIVATE_IP}"
EOF
echo "[common] PRIVATE_IP=${PRIVATE_IP}"
