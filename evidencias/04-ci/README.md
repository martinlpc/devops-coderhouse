# Paso 4: CI con GitHub Actions

Workflow: [ci.yml](../../.github/workflows/ci.yml). Se dispara con cada `push` y cada `pull_request` sobre `main`.

## Qué se automatizó

| Job    | Qué hace                                                                                     |
| ------ | -------------------------------------------------------------------------------------------- |
| `test` | Instala las dependencias con el lockfile congelado y corre el test de la API (Node 24, pnpm) |

Decisiones de seguridad y reproducibilidad:

- `permissions: contents: read` a nivel de workflow (mínimo privilegio): el job solo puede leer el código.
- `pnpm install --frozen-lockfile`: el CI falla si `pnpm-lock.yaml` no coincide con `package.json`, igual que el build de la imagen.
- La versión de pnpm sale del campo `packageManager` de `app/package.json`, así que hay una única fuente de verdad (no se duplica en el workflow).
- Versión de Node (24) igual a la del Dockerfile, para que CI e imagen no difieran.

## Validaciones

| #   | Qué se valida                                           | Cómo                                           | Resultado esperado                                                                        | Evidencia                                                                                                                                            |
| --- | ------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | El workflow se dispara y el job `test` termina en verde | Push a `main` y revisar la pestaña **Actions** | Todos los pasos con tilde: `pnpm/action-setup`, `setup-node`, `pnpm install`, `pnpm test` | [01_ci_test_verde.png](01-ci_test_verde.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/38625600326/job/116063830589) |

## Cómo reproducirlo

En GitHub: hacer un push (o abrir un pull request) hacia `main` y abrir la pestaña **Actions** del repositorio.

El mismo chequeo en local, desde la raíz del repo:

    cd app
    pnpm install --frozen-lockfile
    pnpm test

## Incidente resuelto durante la implementación

El primer run falló en el paso `pnpm/action-setup` con `No pnpm version is specified`. La causa: `defaults.run.working-directory` solo afecta a los pasos `run`, no a las acciones (`uses`), y `pnpm/action-setup` busca por defecto `package.json` en la raíz del repo, donde no está (la app vive en `app/`). Se resolvió indicando la ruta con `package_json_file: app/package.json`.

## Nota sobre las evidencias

Los logs de las ejecuciones de Actions se eliminan pasado cierto período de retención. El enlace a la ejecución sigue existiendo, pero sus logs pueden dejar de estar disponibles, por eso se incluye la captura como evidencia permanente.
