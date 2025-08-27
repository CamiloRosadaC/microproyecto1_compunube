# Microproyecto1 — Consul (opcional) + HAProxy + Web (Node) + Pruebas con Artillery

Proyecto académico de **Computación en la Nube** que levanta:

- 2 VMs **web** (Node HTTP nativo) con `/: Hello` y `/health: OK`
- 1 VM **haproxy** como balanceador (y **stats** dedicadas)
- **Pruebas de carga** con **Artillery** (se instalan manualmente en `haproxy`)

> ⚠️ Solo para fines académicos.

---

## Topología (IPs por defecto)

| VM       | IP             | Rol                                    |
|----------|----------------|----------------------------------------|
| haproxy  | `192.168.100.2`| Balanceador + página de **stats**      |
| web1     | `192.168.100.3`| App Node en puertos **3000** y **3001**|
| web2     | `192.168.100.4`| App Node en puertos **3000** y **3001**|

**Endpoints útiles**

- App vía HAProxy: `http://192.168.100.2/`  
- Stats dedicadas: `http://192.168.100.2:8404/` (user/pass: **admin/admin**)  
- Salud directa:  
  - `http://192.168.100.3:3000/health`, `:3001/health`  
  - `http://192.168.100.4:3000/health`, `:3001/health`

---

## Estructura del proyecto

```
microproyecto1/
│
├── Vagrantfile
├── README.md
│
├── consul/
│   └── services/        # placeholder (vacío por ahora)
│
├── scripts/
│   ├── common.sh        # paquetes base, red, timezone, utilidades
│   ├── haproxy.sh       # instalación/config de HAProxy (+ Consul si se usa)
│   └── web.sh           # app Node, systemd web@PUERTO, (registro Consul)
│
└── tests/               # (no usado aquí; las pruebas viven en ~/tests de haproxy)
```

---

## Levantar el entorno

```bash
vagrant up
```

### Comprobaciones rápidas

1) **HAProxy activo** (en `haproxy`)
```bash
vagrant ssh haproxy
sudo systemctl status haproxy --no-pager
```
**Esperado:** aparece `Active: active (running)`.

2) **Frontend responde**
```bash
curl -sI http://127.0.0.1:80 | head -n1
```
**Esperado:** `HTTP/1.1 200 OK`.

3) **Backends vivos (desde `haproxy`)**
```bash
for h in 3 4; do for p in 3000 3001; do   echo -n "web$((h-2)):$p -> "; curl -sS -m 2 http://192.168.100.$h:$p/health; done; done
```
**Esperado:** cuatro líneas con `OK`.

4) **Servicios en cada web**
```bash
vagrant ssh web1 -c "sudo systemctl status 'web@3000' --no-pager | sed -n '1,5p';                       sudo systemctl status 'web@3001' --no-pager | sed -n '1,5p'"
```
**Esperado:** ambos `Active: active (running)`.

---

## Configuración de HAProxy usada (estática mínima)

> Si necesitas cargarla manualmente en `haproxy`:

```bash
sudo tee /etc/haproxy/haproxy.cfg >/dev/null <<'EOF'
global
    log /dev/log local0
    maxconn 4096
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5s
    timeout client  30s
    timeout server  30s
    timeout check   5s

frontend fe_http
    bind *:80
    default_backend be_web

backend be_web
    balance roundrobin
    # Health check HTTP explícito:
    http-check connect
    http-check send meth GET uri /health ver HTTP/1.1 hdr Host localhost
    http-check expect status 200

    server w1 192.168.100.3:3000 check inter 2s fall 2 rise 1
    server w2 192.168.100.3:3001 check inter 2s fall 2 rise 1
    server w3 192.168.100.4:3000 check inter 2s fall 2 rise 1
    server w4 192.168.100.4:3001 check inter 2s fall 2 rise 1

# Stats dedicadas en :8404
listen stats
    bind *:8404
    stats enable
    stats uri /
    stats refresh 2s
    stats auth admin:admin
EOF

# Validar y reiniciar
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
sudo systemctl restart haproxy
```

**Esperado:**
- `haproxy -c ...` → `Configuration file is valid`.
- `sudo ss -ltnp | grep -E ':80|:8404'` → dos líneas `LISTEN` con `haproxy`.

---

## Abrir la página de la app y la página de stats

- **App:** `http://192.168.100.2/`  
  **Esperado:** una de estas líneas (varía):  
  - `Hola desde web1 en el puerto 3000`  
  - `Hola desde web1 en el puerto 3001`  
  - `Hola desde web2 en el puerto 3000`  
  - `Hola desde web2 en el puerto 3001`  
  (al refrescar, deben alternar — round robin).

- **Stats:** `http://192.168.100.2:8404/`  
  **Esperado:** pide credenciales; con **admin/admin** muestra la tabla:  
  - `fe_http` en **OPEN**  
  - `be_web` con **w1..w4** en **UP (green)** tras 1–3 s.

**Verificación por cURL (opcional):**
```bash
# sin auth
curl -i http://127.0.0.1:8404/ | head -n1
# con auth
curl -su admin:admin -i http://127.0.0.1:8404/ | head -n1
```
**Esperado:**  
- sin auth → `HTTP/1.1 401 Unauthorized`  
- con auth → `HTTP/1.1 200 OK`

---

## Dependencias a instalar en **haproxy** (para Artillery)

> Todo esto **dentro** de `haproxy`:

```bash
# 1) Paquetes base
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg python3 jq

# 2) Node 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v && npm -v
```
**Esperado:** `node v20.x.x` y `npm 10.x`.

```bash
# 3) Artillery global
sudo npm -g install artillery@2.0.21
artillery -V
```
**Esperado:** `2.0.21`.

```bash
# 4) Carpeta de pruebas
mkdir -p ~/tests
```
**Esperado:** `~/tests` creada (silencioso).

---

## Prueba con **Artillery** (qué hace y resultados esperados)

### Qué prueba
Genera **20 req/s por 60 s** contra `http://127.0.0.1:80/` (HAProxy) con un `GET /`.  
Valida balanceo, ausencia de fallos y latencias.

### Ejecutar

```bash
cd ~/tests
cat > plan-20rps-60s.yml <<'YAML'
config:
  target: "http://127.0.0.1:80"
  phases:
    - duration: 60
      arrivalRate: 20
scenarios:
  - flow:
      - get:
          url: "/"
YAML

artillery run plan-20rps-60s.yml -o report-20x60.json
artillery report report-20x60.json -o report-20x60.html
```

**Esperado (consola al final, aproximado):**
```
Scenarios launched: 1200
Scenarios completed: 1200
Requests completed: 1200
Codes: 200 1200
Latency (ms): p50 ~3-20  p95 <100-200  p99 <200-300
Errors: 0
```

### Visualizar el reporte

```bash
python3 -m http.server 8080 --directory ~/tests
```
Abre: `http://192.168.100.2:8080/report-20x60.html`  
**Esperado:** dashboard con **0 Failures**, predominio de **200**, percentiles bajos.

### Extraer números por `jq` (robusto)

```bash
cd ~/tests
# 200s
jq '.aggregate.counters["http.codes.200"] // 0' report-20x60.json
# Latencias
jq '.aggregate.summaries["http.response_time"].p50' report-20x60.json
jq '.aggregate.summaries["http.response_time"].p95' report-20x60.json
jq '.aggregate.summaries["http.response_time"].p99' report-20x60.json
# RPS estimado (si no viene en .aggregate.rates)
jq '( [ .aggregate.counters|to_entries[]|select(.key|startswith("http.codes."))|.value ] | add // 0 ) / 60' report-20x60.json
```
**Esperado (ejemplo):**
- `http.codes.200` ≈ `1200`
- `p50` ≈ `3–20`
- `p95` `< 100–200`
- `p99` `< 200–300`
- RPS ≈ `~20`

---

## Problemas comunes y solución

- **Stats no abre** → usar listener `:8404`, reiniciar y validar:
  ```bash
  sudo haproxy -c -f /etc/haproxy/haproxy.cfg   # Esperado: Configuration file is valid
  sudo systemctl restart haproxy
  sudo ss -ltnp | grep -E ':80|:8404'           # Esperado: LISTEN en ambos
  ```

- **Backends DOWN (L7TOUT)** → chequear `/health` desde `haproxy`:
  ```bash
  for h in 3 4; do for p in 3000 3001; do curl -sS http://192.168.100.$h:$p/health; done; done
  ```
  **Esperado:** cuatro `OK`.  
  Si `node` falta en web:
  ```bash
  # en la web afectada
  which node || which nodejs
  # si solo hay nodejs:
  sudo ln -sf "$(command -v nodejs)" /usr/bin/node
  sudo systemctl restart 'web@3000' 'web@3001'
  ```

- **Error `??` al usar npx/artillery** → Node antiguo.  
  **Esperado tras fix:** `node v20.x.x`, `artillery -V 2.0.21`.

- **`artillery: command not found`**  
  Reinstala global y refresca:
  ```bash
  sudo npm -g install artillery@2.0.21
  hash -r; which artillery; artillery -V
  ```
