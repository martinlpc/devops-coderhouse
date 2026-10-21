# Evidencias

Cada carpeta corresponde a un paso del proyecto e incluye un README con la tabla de validaciones (qué se probó, comando, resultado esperado y archivo de evidencia).

| Paso | Carpeta                                   | Qué demuestra                                                                          |
| ---- | ----------------------------------------- | -------------------------------------------------------------------------------------- |
| 1    | [01-app](01-app/)                         | API Express con `/`, `/health` y `/metrics`, y test automatizado                       |
| 2    | [02-docker](02-docker/)                   | Imagen Docker multi-stage, usuario no root y tamaño reducido                           |
| 3    | [03-k8s](03-k8s/)                         | Cluster Kubernetes local y despliegue de la aplicación                                 |
| 4    | [04-ci](04-ci/)                           | CI/CD Workflows para automatización                                                    |
| 5    | [05-sast](05-sast/)                       | Análisis de seguridad del código (SAST)                                                |
| 6    | [06-hpa](06-hpa/)                         | Autoescalado horizontal con HPA y `metrics-server`                                     |
| 7    | [07-terraform](07-terraform/)             | Infraestructura en AWS con Terraform: red, instancia y cluster k3s                     |
| 8    | [08-terraform-ci](08-terraform-ci/)       | Terraform en el pipeline (`fmt`, `validate`, `plan`) con autenticación OIDC            |
| 9    | [09-deploy-pipeline](09-deploy-pipeline/) | Despliegue en Kubernetes desde el pipeline, sobre un cluster `kind` temporal           |
| 10   | [10-dast](10-dast/)                       | DAST con OWASP ZAP sobre la app desplegada, con corrección de las cabeceras detectadas |
