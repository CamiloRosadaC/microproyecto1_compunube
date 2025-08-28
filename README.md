# Microproyecto: Consul + HAProxy + Apps NodeJS + Artillery

Sistema distribuido que combina **Consul** para descubrimiento de
servicios, **HAProxy** como balanceador de carga dinámico y dos
aplicaciones **NodeJS** desplegadas en máquinas virtuales con
**Vagrant**.\
Se incluyen pruebas de carga con **Artillery** para evaluar desempeño
bajo diferentes escenarios (base, spike y soak).

------------------------------------------------------------------------

## 1) Estructura del proyecto

    consul-haproxy-artillery/
    ├─ Vagrantfile
    ├─ provision/
    │  ├─ 00-common.sh
    │  ├─ 10-consul-install.sh
    │  ├─ 20-consul-server.sh
    │  ├─ 21-consul-client.sh
    │  ├─ 40-node-install.sh
    │  └─ 41-node-service.sh
    ├─ consul/
    │  └─ services/web.json
    ├─ haproxy/
    │  ├─ haproxy.cfg
    │  └─ errors/503.http
    ├─ app/
    │  ├─ app.js
    │  └─ app.service
    └─ tests/
       ├─ artillery.yml      # prueba base
       ├─ artillery_spike.yml
       └─ artillery_soak.yml

**VMs y roles** - **haproxy** → Consul server + HAProxy + DNS de
Consul. - **web1** → App NodeJS + Consul client. - **web2** → App
NodeJS + Consul client.

**Puertos expuestos al host** - Consul UI → `localhost:8500` - HAProxy
frontend → `localhost:8080` o `localhost:2200` (según auto_correct de
Vagrant). - HAProxy stats → `192.168.100.10:8404/haproxy?stats`

------------------------------------------------------------------------

## 2) Scripts de aprovisionamiento

-   **00-common.sh** → prerequisitos, usuario `consul`, directorios y
    permisos.
-   **10-consul-install.sh** → instala Consul + systemd unit.
-   **20-consul-server.sh** → configura Consul server (haproxy).
-   **21-consul-client.sh** → configura agentes cliente (web1, web2).
-   **40-node-install.sh** → instala NodeJS en web1/web2.
-   **41-node-service.sh** → despliega app NodeJS en :3000 y la registra
    en Consul.

------------------------------------------------------------------------

## 3) HAProxy

### Configuración dinámica (recomendada)

Uso de `server-template` con **Consul DNS**:

``` haproxy
backend be_web
  balance roundrobin
  server-template web- 10 _web._tcp.service.consul resolvers consul resolve-prefer ipv4 check
```

> **Nota**: en la página de stats verás `web-1` y `web-2` como UP, y
> otros slots en **MAINT**. Esto es normal: son "espacios reservados"
> para escalar.

### Configuración estática (diagnóstico)

``` haproxy
backend be_web
  balance roundrobin
  server web1 192.168.100.11:3000 check
  server web2 192.168.100.12:3000 check
```

------------------------------------------------------------------------

## 4) Cómo usarlo

1.  **Levantar entorno**

    ``` bash
    vagrant up
    ```

2.  **Verificar puertos**

    ``` bash
    vagrant port haproxy
    ```

    Usar ese puerto para acceder al frontend.

3.  **Pruebas rápidas**

    -   Consul UI → <http://localhost:8500/ui/>

    -   HAProxy frontend → `http://localhost:<PUERTO>`

    -   HAProxy stats → <http://192.168.100.10:8404/haproxy?stats>

    -   Balanceo:

        ``` bash
        for i in {1..6}; do curl -s http://localhost:<PUERTO>/; done
        ```

        Debería alternar entre *web1* y *web2*.

------------------------------------------------------------------------

## 5) Verificación y diagnóstico

En `haproxy`:

``` bash
systemctl status consul haproxy    # ambos active (running)
consul members                     # nodos haproxy, web1, web2 en alive
consul catalog services            # muestra 'consul' y 'web'
```

En `web1` / `web2`:

``` bash
systemctl status consul app@web1   # servicios activos
curl http://127.0.0.1:3000/        # "Hello from web1"
```

Desde el host:

``` bash
curl http://localhost:<PUERTO>/    # Hello from web1 / web2
```

------------------------------------------------------------------------

## 6) Pruebas de carga con Artillery

### Escenarios

-   **Base (tests/artillery.yml)** → 300 requests a 10 rps.
-   **Spike (artillery_spike.yml)** → incremento abrupto hasta 100 rps.
-   **Soak (artillery_soak.yml)** → carga sostenida a 10 rps durante 2
    min.

### Ejecución

``` bash
npx --yes artillery run tests/artillery.yml --output base.json
npx --yes artillery run tests/artillery_spike.yml --output spike.json
npx --yes artillery run tests/artillery_soak.yml --output soak.json
```

------------------------------------------------------------------------

## 7) Resultados de las pruebas

  -------------------------------------------------------------------------
  Escenario   Requests   Errores   Latencia media    p95   p99   Outliers
  ----------- ---------- --------- ----------------- ----- ----- ----------
  Base        300        0         3 ms              4 ms  5 ms  ninguno

  Spike       2100       0         5 ms              6 ms  16 ms algunos
                                                                 \~800 ms

  Soak        1200       0         6.7 ms            4 ms  6 ms  algunos
                                                                 \~1000 ms
  -------------------------------------------------------------------------

### Interpretación

-   **Base**: desempeño perfecto, latencias mínimas y sin fallos.
-   **Spike**: bajo picos de 100 req/s, el sistema sigue estable y sin
    errores; solo aparecen pocos requests con mayor latencia (outliers
    hasta \~859 ms).
-   **Soak**: bajo carga sostenida por 2 min, mantiene consistencia (p95
    = 4 ms), aunque se registran outliers aislados de hasta 1s (posibles
    efectos del entorno virtualizado o GC de NodeJS).
-   **Conclusión**: el sistema es **estable, escalable y altamente
    disponible**, con un excelente rendimiento en condiciones normales y
    buena resiliencia en escenarios extremos.

------------------------------------------------------------------------

## 8) Evidencias 

-   Captura de **Consul UI** con servicios y nodos `web` en verde.
<img width="1898" height="922" alt="image" src="https://github.com/user-attachments/assets/7c720889-bf89-4057-ba3f-31cbee6520f5" />
<img width="1901" height="929" alt="image" src="https://github.com/user-attachments/assets/ffdab6a0-2da7-4836-9d03-985478f901d3" />
<img width="1898" height="922" alt="image" src="https://github.com/user-attachments/assets/e3212100-c57d-4d29-a99b-7899800ab384" />

-   Captura de **HAProxy stats** con `web-1` y `web-2` UP.
<img width="1902" height="930" alt="image" src="https://github.com/user-attachments/assets/028f5ba0-d286-4533-8f60-104f42ac5d1b" />
-   Resumen de Artillery (latencias, RPS).
### Prueba Base (300 requests totales, 10 req/s)
- Éxito total: 300/300 respuestas 200 OK, 0 fallos.
- Latencias:
 - Media ~3.4 ms.
 - p95 = 4 ms, p99 = 5 ms.
 - Muy consistentes y bajas.
- Sesión usuarios: promedio ~5.9 ms de duración.

El sistema responde perfectamente a carga ligera y estable.


### Prueba Spike (2100 requests, pico hasta 100 req/s)

- Éxito total: 2100/2100 respuestas 200 OK, 0 fallos.

- Latencias:
 - Media 5 ms.
 - p95 = 6 ms, p99 = 16 ms.
 - Hubo outliers: máximo 859 ms, p999 ≈ 206 ms (unos pocos requests lentos en el pico).
 - Sesión usuarios: promedio ~7.4 ms, pero algunos hasta ~860 ms.

El sistema aguanta el pico sin errores, aunque bajo carga extrema aparecen unos cuantos requests con mayor latencia. Esto es típico en un spike test.

### Prueba Soak (1200 requests sostenidos, 10 req/s por 2 minutos)

- Éxito total: 1200/1200 respuestas 200 OK, 0 fallos.

-Latencias:
 - Media ~6.7 ms.
 - p95 = 4 ms, p99 = 6 ms → muy buenas.
 - Pero hay outliers raros: máximo ~1023 ms, p999 ≈ 1000 ms.
- Sesión usuarios: promedio ~10 ms, pero algunos con duraciones de hasta 1 segundo.

En carga sostenida el sistema es estable y mantiene buenas métricas, pero se detectan latencias aisladas (probablemente GC de NodeJS, scheduling de la VM o DNS resolver de HAProxy).

-   Captura de página 503 personalizada al simular caída de
    backends.
<img width="1920" height="922" alt="image" src="https://github.com/user-attachments/assets/26391bb4-2086-456a-928b-bc63ceea4726" />
-   (Opcional) Captura de página 503 personalizada al simular caída de
    backends.
