# 📘 Microproyecto 1 — Computación en la Nube

## 📌 Descripción
Este microproyecto implementa un entorno con **HAProxy** que balancea tráfico HTTP hacia múltiples servidores web.  
El funcionamiento se valida con pruebas de carga usando **Artillery**, generando reportes HTML y verificando métricas de latencia, throughput y errores.

---

## ⚙️ Preparación del entorno

1. **Acceder a la VM `haproxy`:**
   ```bash
   vagrant ssh haproxy
   ```

2. **Verificar dependencias:**
   ```bash
   node -v
   npm -v
   artillery -V
   ```
   Debes ver algo como:
   ```
   v20.x.x
   10.x.x
   2.0.21
   ```

---

## 🚀 Ejecución de pruebas con Artillery

1. **Crear carpeta de pruebas:**
   ```bash
   mkdir -p ~/tests
   cd ~/tests
   ```

2. **Crear el plan de prueba (`test.yml`):**
   ```yaml
   config:
     target: "http://192.168.100.2"
     phases:
       - duration: 30
         arrivalRate: 10   # 10 req/s durante 30s
   scenarios:
     - flow:
         - get:
             url: "/"
   ```

3. **Validar el archivo:**
   ```bash
   artillery validate test.yml
   ```

4. **Ejecutar prueba y generar reporte JSON:**
   ```bash
   artillery run test.yml -o report.json
   ```

5. **Generar reporte HTML:**
   ```bash
   artillery report report.json -o report.html
   ```

6. **Servir el reporte en el puerto 8080:**
   ```bash
   python3 -m http.server 8080 --directory ~/tests
   ```

7. **Verificar acceso al reporte:**
   ```bash
   curl -I http://127.0.0.1:8080/report.html
   ```
   Salida esperada:
   ```
   HTTP/1.0 200 OK
   Content-type: text/html
   ```

   👉 En el navegador:  
   `http://192.168.100.2:8080/report.html`

---

## ✅ Validación del correcto funcionamiento

1. **HAProxy Stats**  
   - Abrir en navegador:  
     `http://192.168.100.2/haproxy?stats`  
   - Todos los backends deben estar en **UP** (verde).  

   _Evidencia:_  
   ![haproxy-stats](./evidencias/haproxy-stats.png)

---

2. **Reporte de Artillery**  
   - Debe mostrar:
     - Requests completados ≈ esperados (ej: 300 en 30s).  
     - **HTTP 200** en todos los requests.  
     - **Errores = 0**.  
     - Latencia p95 y p99 en valores bajos (milisegundos).  

   _Evidencia:_  
   ![artillery-report](./evidencias/artillery-report.png)

---

## 📊 Conclusiones
- HAProxy balanceó correctamente entre los servidores.  
- No se registraron errores en 300 peticiones (100% 200 OK).  
- La latencia promedio se mantuvo en ~3 ms (p95 ≈ 6 ms).  
- El sistema respondió de manera estable bajo carga.  

---
