# Paso 4: CI con GitHub Actions

Workflow: [ci.yml](../../.github/workflows/ci.yml). Se dispara con cada `push` y cada `pull_request` sobre `main`.

## Qué se automatizó

| Job              | Qué hace                                                                                         | Cuándo corre                    |
| ---------------- | ------------------------------------------------------------------------------------------------ | ------------------------------- |
| `test`           | Instala las dependencias con el lockfile congelado y corre el test de la API (Node 24, pnpm)     | Push y pull request a `main`    |
| `build-and-push` | Construye la imagen con el Dockerfile multi-stage de `app/` y la publica en GHCR con tag por SHA | Solo push a `main`, tras `test` |

Decisiones de seguridad y reproducibilidad:

- `permissions: contents: read` a nivel de workflow (mínimo privilegio). Solo `build-and-push` recibe además `packages: write`.
- Sin credenciales propias: el login a GHCR usa el `GITHUB_TOKEN` que GitHub genera en cada ejecución.
- `needs: test`: nunca se publica una imagen de código que no pasó el test.
- `if: github.event_name == 'push'`: en un pull request se testea pero no se publica.
- Tag por SHA del commit (`sha-9500218`): cada imagen es trazable al código que la generó. El tag `latest` no se usa porque es mutable.
- `pnpm install --frozen-lockfile`: el CI falla si `pnpm-lock.yaml` no coincide con `package.json`, igual que el build de la imagen.
- La versión de pnpm sale del campo `packageManager` de `app/package.json` (una sola fuente de verdad), y la versión de Node (24) es la del Dockerfile.
- El paquete en GHCR es público para que Kubernetes pueda descargarlo sin credenciales. La imagen no contiene secretos (solo `src` y dependencias de producción).

## Validaciones

| #   | Qué se valida                                               | Comando / acción                                                                                          | Resultado esperado                                                                                          | Evidencia                                                                                                                                            |
| --- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | El job `test` termina en verde                              | Push a `main` y revisar la pestaña **Actions**                                                            | Todos los pasos con tilde: `pnpm install`, `pnpm test`                                                      | [01-ci_test_verde.png](01-ci_test_verde.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/38629403199/job/116076840916) |
| 2   | `build-and-push` corre solo después de `test` y publica     | Push a `main` y revisar la pestaña **Actions**                                                            | Dos jobs en verde, `build-and-push` arranca al terminar `test`                                              | [02-ci_test_build_verdes.png](02-ci_test_build_verdes.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/38629403199)    |
| 3   | La imagen existe en GHCR con tag por SHA                    | Sección **Packages** del repositorio                                                                      | Paquete `devops-coderhouse` con el tag `sha-9500218`                                                        | [06-packages.png](06-packages.png)                                                                                                                   |
| 4   | La imagen se descarga y su digest coincide con el publicado | `docker pull ghcr.io/martinlpc/devops-coderhouse:sha-9500218`                                             | `Digest: sha256:4eed833e05b287004dc162a3900643a834970e4eb22f2da0008e608ff1a95a8a`, igual al del log del job | [03-docker_pull.txt](03-docker_pull.txt)                                                                                                             |
| 5   | La imagen construida en CI responde                         | `docker run --rm -d -p 8081:3000 --name pf-ghcr <imagen>` y `curl.exe -s -i http://localhost:8081/health` | `200 OK` con `{"status":"ok"}`                                                                              | [04-ghcr_health.txt](04-ghcr_health.txt)                                                                                                             |
| 6   | La imagen de CI corre sin root                              | `docker exec pf-ghcr whoami`                                                                              | `node`                                                                                                      | [05-ghcr_whoami.txt](05-ghcr_whoami.txt)                                                                                                             |

## Cómo reproducirlo

En GitHub: hacer un push hacia `main` y abrir la pestaña **Actions** del repositorio.

El mismo chequeo de tests en local, desde la raíz del repo:

    cd app
    pnpm install --frozen-lockfile
    pnpm test

Para probar la imagen publicada por el pipeline (reemplazar el tag por el que figure en **Packages**):

    docker pull ghcr.io/martinlpc/devops-coderhouse:sha-9500218
    docker run --rm -d -p 8081:3000 --name pf-ghcr ghcr.io/martinlpc/devops-coderhouse:sha-9500218
    curl.exe -s -i http://localhost:8081/health
    docker exec pf-ghcr whoami
    docker rm -f pf-ghcr

## Incidente resuelto durante la implementación

El primer run falló en el paso `pnpm/action-setup` con `No pnpm version is specified`. La causa: `defaults.run.working-directory` solo afecta a los pasos `run`, no a las acciones (`uses`), y `pnpm/action-setup` busca por defecto `package.json` en la raíz del repo, donde no está (la app vive en `app/`). Se resolvió indicando la ruta con `package_json_file: app/package.json`.

## Mejoras pendientes (FinOps)

- **Evitar builds innecesarios**: hoy cada push a `main` ejecuta test, construye la imagen y la publica en GHCR, incluso si solo cambian documentación o evidencias. Se deja sin aplicar mientras se prueba el pipeline, para que cada commit lo dispare. Una vez estable, se agrega `paths-ignore` (`evidencias/**`, `**.md`) al trigger `push`, lo que ahorra minutos de runner y espacio en el registry.

## Nota sobre las evidencias

Los logs de las ejecuciones de Actions se eliminan pasado cierto período de retención. El enlace a la ejecución sigue existiendo, pero sus logs pueden dejar de estar disponibles, por eso se incluyen capturas y la salida del `docker pull` (con el digest) como evidencia permanente.
