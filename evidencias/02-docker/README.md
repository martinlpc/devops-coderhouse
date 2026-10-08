# Paso 2: Imagen Docker multi-stage

Imagen `devops-pf-api:1.0.0` construida con el [`Dockerfile`](../../app/Dockerfile) de `app/`.

## Decisiones de diseño

- **Dos stages**: `builder` instala solo dependencias de producción; la imagen final copia únicamente `node_modules` y `src/`, sin herramientas de build.
- **Base fija y liviana**: `node:24-alpine`.
- **Reproducible**: pnpm fijado con el campo `packageManager` y `--frozen-lockfile`.
- **Caché de capas**: se copian primero `package.json` y `pnpm-lock.yaml`, luego el código.
- **Seguridad**: el proceso corre como usuario `node` (no root), `NODE_ENV=production`, y el `.dockerignore` excluye `node_modules`, tests y `.env`.

## Validaciones

| #   | Qué se valida           | Comando                                            | Resultado esperado              | Evidencia              |
| --- | ----------------------- | -------------------------------------------------- | ------------------------------- | ---------------------- |
| 1   | La imagen se construye  | `docker build -t devops-pf-api:1.0.0 .`            | Build sin errores, dos stages   | [build.log](build.log) |
| 2   | El contenedor responde  | `curl.exe -i localhost:3000/health`                | `200 OK` con `{"status":"ok"}`  | <archivo>              |
| 3   | Las métricas se exponen | `curl.exe -s localhost:3000/metrics`               | Formato Prometheus              | <archivo>              |
| 4   | No corre como root      | `docker run --rm devops-pf-api:1.0.0 whoami`       | `node`                          | <archivo>              |
| 5   | Tamaño de la imagen     | `docker images devops-pf-api`                      | Imagen liviana (<size>)         | <archivo>              |
| 6   | Contenedor corriendo    | `docker run --rm -p 3000:3000 devops-pf-api:1.0.0` | Log `Escuchando en puerto 3000` | <captura.png>          |

## Cómo reproducirlo

    cd app
    docker build -t devops-pf-api:1.0.0 .
    docker run --rm -p 3000:3000 devops-pf-api:1.0.0
