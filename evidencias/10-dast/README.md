# Paso 10: DAST con OWASP ZAP

Último paso del job `deploy` de [ci.yml](../../.github/workflows/ci.yml). Escanea la aplicación ya desplegada en el cluster `kind` del runner, entrando por el Ingress como lo haría un cliente real.

## Qué se automatizó

| Paso              | Qué hace                                                             |
| ----------------- | -------------------------------------------------------------------- |
| `zap-baseline.py` | Recorre la aplicación y analiza las respuestas, sin atacarla         |
| Resumen en el log | Imprime el reporte en Markdown dentro del log del job                |
| Barrera de riesgo | Cuenta las alertas medias o altas y falla el pipeline si hay alguna  |
| Artefacto         | Sube los reportes en HTML, Markdown y JSON, incluso si el paso falla |

Se usa el escaneo baseline y no el full scan: el baseline analiza las respuestas de forma pasiva y tarda un par de minutos, mientras que el full scan envía ataques activos (inyecciones, XSS) y tarda mucho más de lo razonable para cada push.

## Cómo llega ZAP a la aplicación

ZAP corre en un contenedor, así que su `localhost` no es el del runner. Dos opciones de `docker run` resuelven eso:

- `--network host`: el contenedor comparte la red del runner y alcanza el puerto 80, donde está el Ingress.
- `--add-host devops-pf.local:127.0.0.1`: resuelve ese nombre dentro del contenedor. Sin esto, ZAP pediría sin la cabecera `Host` que el Ingress necesita y recibiría 404 en todo, con lo que el escaneo no encontraría nada.

La carpeta de reportes se monta en `/zap/wrk` y se le da permiso de escritura con `chmod 777`, porque ZAP corre como usuario sin privilegios dentro del contenedor.

## Hallazgos y correcciones

Primer escaneo: 0 altos, 1 medio, 4 bajos, 1 informativo. Ninguno de inyección ni de autenticación; todos de cabeceras HTTP.

| Hallazgo                                   | Nivel       | Corrección aplicada                                  |
| ------------------------------------------ | ----------- | ---------------------------------------------------- |
| CSP sin `frame-ancestors` ni `form-action` | Medio       | `helmet()` más un manejador de 404 que responde JSON |
| `Cross-Origin-Resource-Policy` ausente     | Bajo        | `helmet()` la fija en `same-origin`                  |
| `Permissions-Policy` ausente               | Bajo        | Middleware propio: helmet no emite esta cabecera     |
| `X-Powered-By: Express`                    | Bajo        | `app.disable('x-powered-by')`                        |
| `X-Content-Type-Options` ausente en `/`    | Bajo        | `helmet()` la fija en `nosniff`                      |
| Contenido cacheable                        | Informativo | `Cache-Control: no-store`                            |

El hallazgo medio necesitaba las dos correcciones juntas. El manejador de errores por defecto de Express responde los 404 con su propia `Content-Security-Policy: default-src 'none'`, que sobrescribe la de helmet, y a esa política le faltan `frame-ancestors` y `form-action`, que no heredan de `default-src`. Con un manejador de 404 propio que devuelve JSON, ese código nunca se ejecuta y la política de helmet queda en todas las respuestas.

Segundo escaneo: **0 altos, 0 medios, 0 bajos**, y una sola alerta informativa.

Esa informativa es la inversa de la anterior: la regla 10049 reporta en los dos sentidos, y ahora avisa que el contenido no es cacheable y que podría beneficiarse de caché. Para una API con respuestas chicas y dinámicas, `no-store` es la decisión buscada, así que se deja como está. Las métricas del escaneo también confirman la corrección: el contenido pasó de 100% `text/html` (las páginas de error de Express) a 100% `application/json`.

Helmet agrega además `X-Frame-Options`, `Referrer-Policy`, `Cross-Origin-Opener-Policy`, `Origin-Agent-Cluster` y `Strict-Transport-Security`. Esta última los navegadores la ignoran sobre HTTP, así que en este entorno no tiene efecto. `X-XSS-Protection: 0` es intencional de helmet: la cabecera está obsoleta y activarla introduce problemas propios.

## La barrera

El paso falla el pipeline si hay alertas de riesgo medio o alto, contadas sobre el JSON del reporte:

```bash
MEDIO_O_ALTO=$(jq '[.site[].alerts[] | select((.riskcode|tonumber) >= 2)] | length' zap/zap-report.json)
```

En el JSON de ZAP, `riskcode` vale 0 informativo, 1 bajo, 2 medio y 3 alto. El umbral está en 2 a propósito: fallar ante cualquier alerta rompería el pipeline hoy mismo por la informativa de caché, que no es un defecto. Las bajas e informativas quedan en el log y en el artefacto sin bloquear.

## Límites del escaneo

- **Solo descubrió 2 endpoints.** El spider navega siguiendo enlaces, y la API devuelve JSON sin enlaces, así que nunca llegó a `/health` ni a `/metrics`. Las tres rutas comparten el mismo middleware, de modo que los hallazgos y las correcciones aplican a todas, pero el escaneo no las verificó una por una. Lo correcto para una API es `zap-api-scan.py` con una definición OpenAPI.
- **`/metrics` queda expuesto al público.** El Ingress enruta todo `/` a la aplicación, así que cualquiera que alcance el host puede leer las métricas, que incluyen versión de Node, uso de memoria y tiempos del proceso. ZAP no lo marcó porque no lo descubrió. Se aborda en el paso de monitoreo.
- Los `/robots.txt` y `/sitemap.xml` que aparecen en los reportes no existen en la aplicación: son rutas que ZAP prueba siempre y que el Ingress manda a Express, que responde 404. De ahí que la mitad de las respuestas sean 4xx.

## Validaciones

| #   | Qué se valida                            | Comando / acción                                | Resultado esperado                                                                    | Evidencia                                                                                                                             |
| --- | ---------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | El escaneo detecta problemas reales      | Paso `DAST con OWASP ZAP`, antes de corregir    | 1 medio, 4 bajos, 1 informativo                                                       | [01-zap_hallazgos_iniciales.md](01-zap_hallazgos_iniciales.md)                                                                        |
| 2   | Las correcciones eliminan los hallazgos  | Mismo paso, después de corregir                 | 0 altos, 0 medios, 0 bajos                                                            | [02-zap_reporte_limpio.md](02-zap_reporte_limpio.md)                                                                                  |
| 3   | La barrera cuenta las alertas de riesgo  | Log del paso                                    | `Alertas de riesgo medio o alto: 0`                                                   | [03-zap_log_pipeline.txt](03-zap_log_pipeline.txt)                                                                                    |
| 4   | El paso corre dentro del pipeline        | Pestaña **Actions**                             | Paso de DAST en verde dentro del job `deploy`                                         | [04-dast_job_verde.png](04-dast_job_verde.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/39651751059) |
| 5   | La imagen publicada trae las cabeceras   | `curl.exe -s -I http://localhost:8081/`         | CSP, `nosniff`, `same-origin`, `Permissions-Policy`, `no-store`, y sin `X-Powered-By` | [05-cabeceras_corregidas.txt](05-cabeceras_corregidas.txt)                                                                            |
| 6   | Los 404 responden JSON con las cabeceras | `curl.exe -s -i http://localhost:8081/noexiste` | `404` con `{"error":"Not found"}` y la CSP de helmet                                  | [06-cabeceras_404.txt](06-cabeceras_404.txt)                                                                                          |

## Cómo reproducirlo

En el pipeline corre solo con cada push a `main`. En local, contra la imagen publicada:

```powershell
$tag = "sha-" + (git rev-parse --short=7 HEAD)
docker run --rm -d -p 8081:3000 --name pf-zap ghcr.io/martinlpc/devops-coderhouse:$tag
New-Item -ItemType Directory -Force zap | Out-Null

docker run --rm -v "$($PWD.Path)\zap:/zap/wrk:rw" ghcr.io/zaproxy/zaproxy:stable `
  zap-baseline.py -t http://host.docker.internal:8081 `
  -r zap-report.html -w zap-report.md -J zap-report.json

Get-Content zap\zap-report.md
docker rm -f pf-zap
```

En local se usa `host.docker.internal` en lugar de `--network host`, porque Docker Desktop en Windows no comparte la red del equipo igual que un runner Linux. Al pegarle directo al contenedor no hace falta la cabecera `Host`, ya que no hay Ingress en el medio.

## Mejoras pendientes

- **Escaneo de API con OpenAPI**: agregar una definición y usar `zap-api-scan.py` para cubrir los tres endpoints de forma explícita.
- **Full scan periódico**: el escaneo activo no tiene sentido en cada push, pero sí programado una vez por semana.
- **Archivo de reglas**: `zap-baseline.py` acepta un archivo que marca reglas como ignoradas o como fallo. Permitiría afinar la barrera por regla en lugar de hacerlo por nivel de riesgo.
