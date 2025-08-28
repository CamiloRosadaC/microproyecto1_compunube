# Microproyecto: Consul + HAProxy + Apps NodeJS + Artillery

Balanceador HAProxy con **descubrimiento dinámico de servicios** vía
**Consul** y dos aplicaciones NodeJS distribuidas en VMs independientes,
todo aprovisionado con **Vagrant**. Incluye pruebas de carga con
**Artillery**.

------------------------------------------------------------------------

## 1) Estructura del proyecto

    consul-haproxy-artillery/
    ├─ Vagrantfile
    ├─ provision/
    │  ├─ 00-common.sh               # prerequisitos, usuario/directorios de Consul, dos2unix
    │  ├─ 10-consul-install.sh       # instala Consul y unit systemd (todos los nodos)
    │  ├─ 20-consul-server.sh        # configura Consul *server* (solo VM haproxy)
    │  ├─ 21-consul-client.sh        # configura Consul *client* (web1 y web2)
    │  ├─ 40-node-install.sh         # instala NodeJS LTS y crea /opt/app
    │  └─ 41-node-service.sh         # app.js + systemd templated app@<NAME>.service + registro en Consul
    ├─ consul/
    │  ├─ server.hcl                 # (opcional si prefieres copiar desde repo)
    │  ├─ client.hcl                 # (opcional si prefieres copiar desde repo)
    │  └─ services/
    │     └─ web.json                # definición del servicio web + health check HTTP
    ├─ haproxy/
    │  ├─ haproxy.cfg                # cfg dinámico con Consul DNS y server-template
    │  └─ errors/503.http            # página 503 personalizada (opcional)
    ├─ app/
    │  ├─ app.js                     # servidor HTTP simple (puerto 3000)
    │  └─ app.service                # plantilla systemd (si no usas la generada por script)
    └─ tests/
       └─ artillery.yml              # escenario de carga (opcional; también puedes usar `artillery quick`)

**VMs y roles** - **haproxy**: Consul **server** + HAProxy + (opcional)
Consul DNS (8600). IP privada `192.168.100.10`. - **web1**: App NodeJS +
Consul **client**. IP privada `192.168.100.11`. - **web2**: App NodeJS +
Consul **client**. IP privada `192.168.100.12`.

**Puertos expuestos al host (forwarded ports)** - Consul UI: **guest
8500 → host 8500** - HAProxy frontend: **guest 8080 → host 8080** (si
está libre) o **host 2200** si Vagrant activa `auto_correct`. - HAProxy
stats (8404) normalmente **solo en la red privada**. Puedes forwardearlo
si deseas.

> Importante: verifica con `vagrant port haproxy` el puerto de **host**
> asignado a 8080; si ves `8080 (guest) => 2200 (host)`, deberás usar
> `http://localhost:2200/`.

------------------------------------------------------------------------

## 2) Qué hace cada script

*(explicaciones como antes, sin cambios)*

------------------------------------------------------------------------

## 3) HAProxy (configuración)

*(explicaciones como antes, incluye nota de server-template con MAINT)*

------------------------------------------------------------------------

## 4) Cómo correr todo (paso a paso)

*(explicaciones como antes)*

------------------------------------------------------------------------

## 5) Instalaciones **manuales**

*(explicaciones como antes)*

------------------------------------------------------------------------

## 6) Verificación y diagnóstico

**En `haproxy`:**

``` bash
systemctl status --no-pager consul haproxy
```

*Esperado:* ambos servicios `active (running)`.

``` bash
consul members
```

*Esperado:* lista de nodos `haproxy`, `web1`, `web2` con estado `alive`
y direcciones `192.168.100.x`.

``` bash
consul catalog services
```

*Esperado:* al menos `consul` y `web`.

``` bash
curl -s http://127.0.0.1:8500/v1/health/service/web?passing | jq '.[].Service.Address'
```

*Esperado:* direcciones de `web1` y `web2` (`192.168.100.11`,
`192.168.100.12`).

``` bash
ss -ltnp | grep -E '(:8080|:8404|:8500)'
```

*Esperado:* sockets escuchando en 8080 (HAProxy frontend), 8404 (stats)
y 8500 (Consul UI).

------------------------------------------------------------------------

**En `web1` / `web2`:**

``` bash
systemctl status --no-pager consul 'app@<NAME>'
```

*Esperado:* ambos servicios `active (running)`.

``` bash
curl -s http://127.0.0.1:3000/
```

*Esperado:* respuesta `Hello from web1` o `Hello from web2`.

``` bash
ls -l /etc/consul.d && cat /etc/consul.d/web.json
```

*Esperado:* archivo `web.json` con definición del servicio y permisos
`-rw-r----- consul consul`.

------------------------------------------------------------------------

**Desde el host:**

``` bash
vagrant port haproxy
```

*Esperado:* mapping `8080 (guest) => <HOSTPORT>` y
`8500 (guest) => 8500`.

``` bash
curl http://localhost:<HOSTPORT_8080>/
```

*Esperado:* respuesta `Hello from web1` o `Hello from web2`.

``` powershell
Start-Process "http://localhost:8500/ui/"
```

*Esperado:* interfaz gráfica de Consul mostrando servicios `web` en
verde (passing).

------------------------------------------------------------------------

**Problemas comunes y soluciones** - *Multiple private IPv4 addresses
found* → define `bind_addr` y `advertise_addr` a la IP `192.168.100.x`
(los scripts ya lo hacen). - *permission denied /etc/consul.d* →
asegúrate de `chown consul:consul` y `chmod 640` en archivos
`.hcl/.json` y `750` en directorios. - Frontend no abre en `:8080` →
revisa `vagrant port haproxy` (puede ser `2200`),
`systemctl status haproxy` y `ss -ltnp | grep :8080`. - No aparecen
backends en stats → valida `curl 127.0.0.1:3000` en web1/web2 y que
`web.json` exista y pase `consul validate`.

------------------------------------------------------------------------

## 7) Extensiones (opcional / puntos extra)

*(igual que antes)*

------------------------------------------------------------------------

## 8) Evidencias sugeridas para el informe

*(igual que antes, incluye nota de slots MAINT en stats)*
