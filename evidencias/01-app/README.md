# Paso 1: API Express

API mínima en Node.js + Express (código en [`app/src`](../../app/src)) con tres endpoints GET y un test automatizado.

| Endpoint       | Descripción                                         |
| -------------- | --------------------------------------------------- |
| `GET /`        | Mensaje y versión de la API                         |
| `GET /health`  | Estado de salud, lo usarán los probes de Kubernetes |
| `GET /metrics` | Métricas en formato Prometheus (`prom-client`)      |

## Validaciones

| #   | Qué se valida                          | Comando                              | Resultado esperado                                                        | Evidencia                          |
| --- | -------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------- | ---------------------------------- |
| 1   | El test automatizado pasa              | `pnpm test`                          | Test en verde, sin fallos                                                 | [test.log](test.log)               |
| 2   | La raíz responde                       | `curl.exe -i localhost:3000/`        | `200 OK` con JSON de mensaje y versión                                    | [get-root.txt](get-root.txt)       |
| 3   | El health check responde               | `curl.exe -i localhost:3000/health`  | `200 OK` con `{"status":"ok"}`                                            | [get-health.txt](get-health.txt)   |
| 4   | Se exponen métricas                    | `curl.exe -s localhost:3000/metrics` | Texto en formato Prometheus (`# HELP`, `# TYPE`, `process_*`, `nodejs_*`) | [get-metrics.txt](get-metrics.txt) |
| 5   | Historial de commits al cerrar el paso | `git log --oneline`                  | Commits descriptivos                                                      | [git-log.txt](git-log.txt)         |

## Cómo reproducirlo

    cd app
    pnpm install
    pnpm test
    pnpm start

Con la app levantada, los `curl.exe` de la tabla desde otra terminal (PowerShell).
