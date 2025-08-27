#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ---------- utilidades ----------
log() { echo "[common] $*"; }

# Ejecutar como root si es necesario (por si el provisioner no usa root)
if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

export DEBIAN_FRONTEND=noninteractive

# ---------- paquetes base ----------
log "apt-get update (con reintentos)"
apt-get -o Acquire::Retries=3 update -y

log "instalando utilidades base (sin recommends)"
apt-get install -y --no-install-recommends \
  ca-certificates gnupg lsb-release apt-transport-https \
  curl unzip jq \
  dnsutils iproute2 net-tools \
  software-properties-common

# Limpieza ligera de cache
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true

# ---------- zona horaria (opcional, coherente con Colombia) ----------
if command -v timedatectl >/dev/null 2>&1; then
  CURRENT_TZ="$(timedatectl show -p Timezone --value || true)"
  if [[ "${CURRENT_TZ:-}" != "America/Bogota" ]]; then
    log "configurando zona horaria a America/Bogota"
    timedatectl set-timezone America/Bogota || true
  fi
fi

# ---------- detección de IP privada en 192.168.100.0/24 ----------
# Preferimos iproute2; caemos a hostname -I si no hay match
PRIVATE_IP="$(ip -4 addr show | awk '/inet 192\.168\.100\./ {print $2}' | cut -d/ -f1 | head -n1 || true)"
if [[ -z "${PRIVATE_IP}" ]]; then
  PRIVATE_IP="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^192\.168\.100\.' | head -n1 || true)"
fi
PRIVATE_IP="${PRIVATE_IP:-}"

# ---------- export para sesiones interactivas ----------
install -d -m 0755 /etc/profile.d
cat >/etc/profile.d/microproyecto.sh <<'EOF'
# Variables de conveniencia para el microproyecto
# (se cargan en shells de login)
export PRIVATE_IP="${PRIVATE_IP}"
EOF

# Sustituimos el placeholder con el valor encontrado (si lo hay)
if [[ -n "${PRIVATE_IP}" ]]; then
  sed -i "s|\${PRIVATE_IP}|${PRIVATE_IP}|g" /etc/profile.d/microproyecto.sh
fi
chmod 0644 /etc/profile.d/microproyecto.sh

log "PRIVATE_IP=${PRIVATE_IP:-no-detectada}"
log "common.sh finalizado"

