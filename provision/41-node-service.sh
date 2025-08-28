#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-$(hostname)}"

# App HTTP simple
sudo tee /opt/app/app.js >/dev/null <<'JS'
const http = require('http');
const os = require('os');
const name = process.env.APP_NAME || os.hostname();
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type':'text/plain'});
  res.end(`Hello from ${name}\n`);
});
server.listen(3000, () => console.log(`Listening on 3000 - ${name}`));
JS
sudo chown -R www-data:www-data /opt/app

# Unidad systemd templated
sudo tee /etc/systemd/system/app@.service >/dev/null <<'UNIT'
[Unit]
Description=Node Web App (%i)
After=network.target
[Service]
Environment=APP_NAME=%i
ExecStart=/usr/bin/node /opt/app/app.js
Restart=always
User=www-data
Group=www-data
[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now "app@${APP_NAME}.service"

# Registro en Consul
sudo mkdir -p /etc/consul.d
sudo tee /etc/consul.d/web.json >/dev/null <<'JSON'
{
  "service": {
    "name": "web",
    "port": 3000,
    "checks": [
      {
        "id": "web-http",
        "name": "HTTP on :3000",
        "http": "http://127.0.0.1:3000/",
        "interval": "10s",
        "timeout": "2s"
      }
    ]
  }
}
JSON

sudo chown -R consul:consul /etc/consul.d
sudo chmod 640 /etc/consul.d/*.json
sudo consul validate /etc/consul.d || true
sudo systemctl restart consul || true
