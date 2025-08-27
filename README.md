# 📘 Microproyecto 1 — Computación en la Nube (HAProxy + Pruebas con Artillery)

## 🧭 Objetivo
Desplegar un entorno sencillo de **balanceo de carga** con **HAProxy** frente a varios servidores web y **validar su funcionamiento y rendimiento** mediante pruebas de carga con **Artillery**.  
El resultado es un **informe reproducible** con pasos, comandos, salidas esperadas y un **reporte HTML** para evidencias.

---

## 🏗️ Arquitectura (vista lógica)
```
[ Clientes / Artillery ]  -->  [ HAProxy (frontend:80) ]  -->  [ web1, web2, web3, web4 ]
                                      |                                 (HTTP 200)
                                      +--> /haproxy?stats  (página de estadísticas)
```
- **HAProxy** reparte solicitudes HTTP entrantes a los **backends** (web1..web4).
- **Artillery** simula usuarios/requests, mide latencias/errores y genera reportes.

---

## 🗂️ Estructura del proyecto (sugerida)
```
microproyecto1/
├─ Vagrantfile                # Define VMs, recursos y redes (incluye VM 'haproxy')
├─ scripts/                   # (Opcional) scripts de aprovisionamiento
│  ├─ install_haproxy.sh      # instala y configura HAProxy
│  └─ install_node_artillery.sh# instala Node/npm/Artillery cuando se requiera
├─ tests/                     # pruebas de carga y reportes
│  ├─ test.yml                # plan de prueba Artillery (30s @ 10 req/s)
│  ├─ report.json             # salida JSON (se genera tras la prueba)
│  └─ report.html             # reporte HTML (se genera tras la prueba)
└─ evidencias/                # capturas (HAProxy stats, reporte HTML, etc.)
   ├─ haproxy-stats.png
   └─ artillery-report.png
```

> **Nota:** si ya tienes tu estructura real, adapta los nombres. Esta guía funciona igual con rutas equivalentes.

---

## 🧾 ¿Qué hace el `Vagrantfile`?
- **Define** las máquinas virtuales (por ejemplo, `haproxy` y, si aplica, otras VMs).
- **Configura** recursos: **RAM, CPU, hostname** y **redes** (IP estática para acceso desde el host).
- **Sincroniza** carpetas del host a la VM (por ejemplo, para guardar evidencias).
- (Opcional) **Aprovisiona**: ejecuta **scripts** post-boot para instalar HAProxy, Node o dejar configurados servicios.

> En este microproyecto, trabajamos directamente **dentro de la VM `haproxy`** para correr Artillery y acceder a `haproxy?stats` y al **reporte HTML** servido en el puerto 8080.

---

## 🧪 ¿Qué hace cada script? (sugerencia)
Si usas scripts en `scripts/`:

- **`install_haproxy.sh`**  
  Instala HAProxy, coloca un `haproxy.cfg` con frontend en `:80` y define backends (`web1..web4`).  
  Habilita la página de **stats** (`/haproxy?stats`). Reinicia/enable el servicio.

- **`install_node_artillery.sh`**  
  Instala **Node.js** (recomendado **v20 LTS** con `nvm` o NodeSource), **npm**, y **Artillery** (`npm i -g artillery@2.0.21`).  
  Verifica versiones y deja preparado el entorno para pruebas.

> Si no tienes estos scripts, puedes seguir los **comandos directos** de este README y lograr lo mismo.

---

## ⚙️ Preparación del entorno (dentro de la VM)

1) **Entrar a la VM `haproxy`:**
```bash
vagrant ssh haproxy
```
Prompt esperado:
```
vagrant@haproxy:~$
```

2) **Verificar dependencias:**
```bash
node -v
npm -v
artillery -V
```
**Salida esperada (ejemplo estable):**
```
v20.11.1
10.8.2
2.0.21
```

> Si ves **Node v18** y falla Artillery con `File is not defined`, instala Node 20 con **nvm**:
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source "$HOME/.nvm/nvm.sh"
nvm install 20
nvm use 20
nvm alias default 20
node -v  # ahora v20.x.x
npm -v
npm i -g artillery@2.0.21
artillery -V
```

---

## 🚀 Prueba de carga con Artillery (paso a paso)

1) **Crear carpeta de pruebas:**
```bash
mkdir -p ~/tests
cd ~/tests
```

2) **Crear el plan de prueba** `test.yml` (30s a ~10 req/s):
```yaml
config:
  target: "http://192.168.100.2"
  phases:
    - duration: 30
      arrivalRate: 10   # 10 req/s durante 30s
scenarios:
  - name: "GET raíz"
    flow:
      - get:
          url: "/"
```

3) **Validar el archivo:**
```bash
artillery validate test.yml
```
**Salida esperada:**
```
File test.yml is valid.
```

4) **Ejecutar la prueba y generar reporte JSON:**
```bash
artillery run test.yml -o report.json
```
**Salida esperada (resumen realista):**
```
Phase started: unnamed (index: 0, duration: 30s) ...

... (métricas por tramo) ...

All VUs finished. Total time: 31 seconds

Summary report @ ...
http.codes.200: ............................................................... 300
http.requests: ................................................................ 300
http.responses: ............................................................... 300
vusers.created: ................................................................ 300
vusers.completed: .............................................................. 300
vusers.failed: ................................................................. 0
http.response_time:
  min: ......................................................................... 0
  max: ......................................................................... 25
  mean: ........................................................................ 2.9
  median: ...................................................................... 3
  p95: ......................................................................... 6
  p99: ......................................................................... 12.1

Log file: /home/vagrant/tests/report.json
```

5) **Generar el reporte HTML:**
```bash
artillery report report.json -o report.html
```
**Salida esperada:**
```
Report generated: /home/vagrant/tests/report.html
```

6) **Servir el reporte HTML en 8080:**
```bash
python3 -m http.server 8080 --directory ~/tests
```
En otra terminal (o desde el host):
```bash
curl -I http://192.168.100.2:8080/report.html
```
**Salida esperada:**
```
HTTP/1.0 200 OK
Content-Type: text/html
```

---

## 🔎 ¿Cómo interpretar la salida de Artillery?

- **`http.codes.200`**: número de respuestas HTTP **200 OK**.  
  - Esperado: igual al total de `http.responses` (si todo responde bien).

- **`vusers.created` / `vusers.completed` / `vusers.failed`**: usuarios virtuales lanzados, terminados y fallidos.  
  - Esperado: `created == completed` y `failed = 0`.

- **`http.request_rate`**: requests por segundo enviados (RPS).  
  - Debe acercarse a `arrivalRate` configurado (aquí ~10 req/s).

- **`http.response_time` (min/mean/median/p95/p99/max)**: latencias en **ms**.  
  - **`p95`** y **`p99`** muestran colas largas/peores casos.  
  - Valores de ejemplo excelentes en tu entorno: `p95 ≈ 6 ms`, `p99 ≈ 12 ms`.

- **`http.downloaded_bytes`**: bytes recibidos. Útil para dimensionar tráfico.

> **Regla rápida:**  
> - Si **p95** sube mucho al aumentar la carga (o aparecen **5xx/4xx**, o `vusers.failed > 0`), hay **saturación**/problemas de backends o red.

---

## 🧪 Validaciones “rápidas” (sanity checks)

### 1) Ver que la web responde 200
```bash
curl -I http://192.168.100.2/
```
**Salida esperada:**
```
HTTP/1.1 200 OK
```

### 2) Ver la página de estadísticas de HAProxy
Abrir en navegador:  
```
http://192.168.100.2/haproxy?stats
```
**Esperado:** todos los backends **UP** (verde) y contador de requests en aumento.

### 3) Ver que el reporte HTML esté disponible
```bash
curl -I http://192.168.100.2:8080/report.html
```
**Esperado:**
```
HTTP/1.0 200 OK
Content-Type: text/html
```

---

## 🧯 Troubleshooting (errores comunes)

- **`ReferenceError: File is not defined` al usar Artillery**  
  → Estás en **Node v18**. Solución: usar **Node v20** con `nvm` (ver sección de preparación).

- **`Codes 404/403/5xx` en Artillery**  
  → La URL o backends no sirven `/`. Valida con `curl -I` y corrige `url` en `test.yml`.

- **No carga `report.html` en el navegador**  
  → Asegura que el server Python esté activo en `haproxy` y que accedes a `http://192.168.100.2:8080/report.html`.  
  → Si usas Vagrant con port-forwarding, confirma los puertos con `vagrant port haproxy`.

- **HAProxy muestra algún backend DOWN**  
  → Revisa servicio web en ese backend (Apache/Nginx), firewall y salud (`/` responde 200).

---

## 📸 Evidencias sugeridas
- Captura de `haproxy?stats` con backends **UP**.  
- Captura del **resumen** de Artillery (con 300 requests, 0 fails, p95).  
- Captura del **report.html** abierto en el navegador.

> Guarda las imágenes en `evidencias/` y enlázalas en este README:
```markdown
![HAProxy Stats](./evidencias/haproxy-stats.png)
![Reporte Artillery](./evidencias/artillery-report.png)
```

---

## ✅ Conclusiones esperadas (ejemplo)
- Se enviaron **300 requests** en 30 segundos (~10 req/s).  
- **0 errores** y **100% 200 OK**.  
- Latencia **media ≈ 3 ms**, **p95 ≈ 6 ms**, **p99 ≈ 12 ms**.  
- El balanceador **HAProxy** distribuyó correctamente la carga y el sistema respondió de forma **estable**.

---
