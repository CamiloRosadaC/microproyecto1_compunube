#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
log(){ echo "[artillery-setup] $*"; }

# Auto-elevación
if [[ "$(id -u)" -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi
export DEBIAN_FRONTEND=noninteractive

log "Actualizando APT"
apt-get -o Acquire::Retries=3 update -y
apt-get install -y --no-install-recommends ca-certificates curl gnupg

# --- Node.js 20 LTS desde NodeSource (remueve nodejs viejo si hubiese) ---
if dpkg -l | grep -q '^ii  nodejs '; then
  log "Removiendo nodejs antiguo de la distro"
  apt-get remove -y nodejs || true
  apt-get autoremove -y || true
fi
log "Instalando Node.js 20.x (NodeSource)"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Asegura binarios
command -v node >/dev/null 2>&1 || ln -sf "$(command -v nodejs)" /usr/bin/node

# --- Artillery global ---
log "Instalando Artillery@2 global"
# asegura prefijo global en /usr/local (para /usr/local/bin)
npm config set prefix /usr/local
npm -g install artillery@2

# symlinks robustos (sesiones no-interactivas ssh -c)
ART_BIN_DIR="$(npm bin -g 2>/dev/null || echo /usr/local/bin)"
ART_PATH="${ART_BIN_DIR%/}/artillery"
install -d /usr/local/bin
if [[ -x "$ART_PATH" ]]; then
  ln -sf "$ART_PATH" /usr/local/bin/artillery
  ln -sf "$ART_PATH" /usr/bin/artillery
fi

# Refuerza PATH de sesiones no-interactivas
if ! grep -q "/usr/local/bin" /etc/environment; then
  if grep -q '^PATH=' /etc/environment; then
    sed -i 's|^PATH="\([^"]*\)"|PATH="\1:/usr/local/bin"|' /etc/environment || true
  else
    echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
  fi
fi

# Carpeta sincronizada de tests
install -d -m 0755 /home/vagrant/tests
chown -R vagrant:vagrant /home/vagrant/tests || true

# Plan por defecto si está vacío
if [[ -z "$(ls -A /home/vagrant/tests 2>/dev/null || true)" ]]; then
  log "Creando plan.yml de ejemplo"
  cat >/home/vagrant/tests/plan.yml <<'YAML'
config:
  target: "http://127.0.0.1:80"
  phases:
    - duration: 30
      arrivalRate: 10
scenarios:
  - flow:
      - get:
          url: "/"
YAML
  chown vagrant:vagrant /home/vagrant/tests/plan.yml || true
fi

# Helper que no depende de PATH del host
cat >/usr/local/bin/artillery-report <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
plan="${1:-plan.yml}"
json="${2:-report.json}"
html="${3:-report.html}"
cd /home/vagrant/tests

# Resuelve artillery de forma robusta
if command -v artillery >/dev/null 2>&1; then
  ART="artillery"
else
  ART="$(npm bin -g 2>/dev/null)/artillery"
  [[ -x "$ART" ]] || ART="/usr/local/bin/artillery"
  [[ -x "$ART" ]] || ART="/usr/bin/artillery"
fi
"$ART" run "$plan" -o "$json"
npx -y artillery@2 report "$json" -o "$html"
echo "Reporte generado: /home/vagrant/tests/$html"
EOF
chmod +x /usr/local/bin/artillery-report

log "Listo. node=$(node -v 2>/dev/null) npm=$(npm -v 2>/dev/null) artillery=$({ artillery -V 2>/dev/null || echo 'no-PATH'; })"


