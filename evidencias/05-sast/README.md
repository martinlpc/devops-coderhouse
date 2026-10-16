# Paso 5: SAST con CodeQL

Workflow: [codeql.yml](../../.github/workflows/codeql.yml). Se dispara con cada `push` y cada `pull_request` sobre `main`, de forma independiente de `ci.yml`.

## Qué se automatizó

| Job       | Qué hace                                                                                                   |
| --------- | ---------------------------------------------------------------------------------------------------------- |
| `analyze` | Analiza el código fuente de la API con CodeQL (`javascript-typescript`) y sube los resultados a Code scanning |

SAST (Static Application Security Testing) examina el código **sin ejecutarlo**: CodeQL lo convierte en una base de datos consultable y corre consultas de seguridad sobre ella, por ejemplo flujos de datos del usuario hacia puntos peligrosos.

Decisiones de diseño y seguridad:

- **Workflow propio y no el "default setup" de GitHub**: el análisis queda versionado en el repo y automatizado dentro del pipeline, como pide la consigna. El workflow subió sus resultados sin conflicto, así que la configuración por defecto de Code scanning no está habilitada.
- **Workflow separado de `ci.yml`**: el análisis no bloquea el build ni la publicación de la imagen, y cada uno falla y se lee por separado.
- **Mínimo privilegio**: `contents: read` a nivel de workflow. El job `analyze` suma `security-events: write` (necesario para subir los resultados) y `actions: read`, y nada más.
- **`build-mode: none`**: JavaScript no se compila, así que CodeQL analiza los fuentes directamente y no hace falta un paso de build.
- **`init` y `analyze` con la misma versión mayor** de `github/codeql-action`, porque comparten formato interno.
- **`category: "/language:javascript-typescript"`**: identifica el análisis, para que los resultados no se mezclen si se suman lenguajes.
- **Repositorio público**: Code scanning con CodeQL es gratuito, sin necesidad de licencias adicionales.

## Validaciones

| #   | Qué se valida                                  | Cómo                                                              | Resultado esperado                                           | Evidencia                                                                      |
| --- | ---------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| 1   | El análisis se dispara y termina en verde      | Push a `main` y revisar la pestaña **Actions**                    | Job `analyze` con todos los pasos con tilde                  | [01-codeql_run_verde.png](01-codeql_run_verde.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/38909807934) |
| 2   | Los resultados llegan a Code scanning          | **Security → Code scanning** en el repositorio                    | Análisis de `javascript-typescript` listado, sin alertas abiertas | [02-code_scanning_sin_alertas.png](02-code_scanning_sin_alertas.png)           |

## Cómo reproducirlo

En GitHub: hacer un push (o abrir un pull request) hacia `main`, esperar a que termine el workflow `CodeQL (SAST)` en la pestaña **Actions** y revisar **Security → Code scanning**.

Prerrequisito: que el default setup de Code scanning no esté habilitado en **Settings → Code security**. Si lo está, el análisis falla al subir los resultados porque no admite una configuración avanzada al mismo tiempo.

## Interpretación del resultado

Cero alertas significa que las consultas estándar de CodeQL no encontraron patrones inseguros en el código analizado. No significa que la aplicación esté libre de vulnerabilidades: SAST ve el código, pero no el comportamiento en ejecución (encabezados HTTP, configuración del servidor, despliegue). Eso lo cubre el análisis dinámico (DAST), que se agrega más adelante al pipeline y ataca la aplicación corriendo.

## Si el análisis encontrara alertas

Cada alerta de Code scanning indica regla, archivo, línea y el flujo de datos que la originó. El procedimiento es evaluar si es un problema real o un falso positivo, corregir el código en el primer caso o descartarla con justificación en el segundo, y volver a ejecutar el workflow para confirmar que desaparece.
