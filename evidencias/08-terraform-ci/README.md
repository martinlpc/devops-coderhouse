# Paso 8: Terraform en el pipeline con OIDC

Workflow: [terraform.yml](../../.github/workflows/terraform.yml). Se dispara solo cuando cambia `terraform/**` o el propio workflow.

## Qué se automatizó

| Paso                   | Qué hace                                                                | Necesita credenciales |
| ---------------------- | ----------------------------------------------------------------------- | --------------------- |
| `terraform fmt -check` | Falla si el código no está formateado, en lugar de reformatearlo        | No                    |
| `terraform init`       | Descarga el provider con las versiones fijadas en `.terraform.lock.hcl` | No                    |
| `terraform validate`   | Verifica la sintaxis y las referencias entre módulos                    | No                    |
| `terraform plan`       | Consulta la API de AWS y muestra qué recursos se crearían               | Sí, de solo lectura   |

El `apply` queda fuera del pipeline a propósito. Cada ejecución crearía una instancia EC2 que factura por hora, y el state es local, así que el runner no sabría qué existe ya. Se ejecuta a mano en una ventana corta (ver [paso 7](../07-terraform/)).

## Autenticación sin claves (OIDC)

El runner no guarda claves de AWS. En cada ejecución, GitHub emite un token firmado y de corta vida, AWS lo valida y devuelve credenciales temporales.

| Recurso en AWS                                       | Para qué                                                                           |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Proveedor OIDC `token.actions.githubusercontent.com` | Declara que la cuenta confía en los tokens que firma GitHub Actions                |
| Rol `github-actions-terraform-plan`                  | Lo que GitHub asume. Su política de confianza limita qué ejecuciones pueden usarlo |

Decisiones de seguridad:

- Sin credenciales permanentes en GitHub. El único secreto del repositorio es `AWS_ROLE_ARN`, que es un identificador, no una clave: sin cumplir la condición de confianza no sirve para nada.
- `permissions` a nivel de job: `contents: read` e `id-token: write`. El segundo es lo que habilita pedir el token OIDC.
- El rol solo tiene `AmazonEC2ReadOnlyAccess`. Alcanza para un `plan` y no puede crear, modificar ni borrar nada.
- La política de confianza acepta solo las ejecuciones de este repositorio, sobre `main` o desde un pull request. Cualquier otro repositorio queda afuera.
- `TF_VAR_allowed_cidr` usa `203.0.113.10/32`, una IP reservada para documentación. El `plan` no se conecta a la instancia, así que no hace falta una IP real.
- `TF_VAR_aws_profile: ""` deja vacío el perfil de AWS CLI: en el runner no existe `terraform-pf`, y vacío el provider usa las credenciales temporales del rol.
- La clave SSH del runner se genera al vuelo y se descarta con el job. Existe solo para que `file(pathexpand(var.ssh_public_key_path))` encuentre un archivo.

## FinOps

Separar este workflow de `ci.yml` evita trabajo inútil en los dos sentidos: un cambio en `terraform/` ya no reconstruye ni publica la imagen de la aplicación, y un cambio en `app/` no ejecuta Terraform. Los tres primeros pasos no consumen nada de AWS, y el `plan` solo hace consultas de lectura, que no se facturan.

## Validaciones

| #   | Qué se valida                      | Comando / acción                                                                                                   | Resultado esperado                                                                            | Evidencia                                                                                                                                                                  |
| --- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | El proveedor OIDC está configurado | `aws iam get-open-id-connect-provider --open-id-connect-provider-arn …`                                            | `Url: token.actions.githubusercontent.com` y `ClientIDList: sts.amazonaws.com`                | [01-oidc_provider.txt](01-oidc_provider.txt)                                                                                                                               |
| 2   | La confianza se limita a este repo | `aws iam get-role --role-name github-actions-terraform-plan --query Role.AssumeRolePolicyDocument`                 | Condición sobre `aud` y `sub`, con los patrones del repositorio                               | [02-rol_politica_confianza.txt](02-rol_politica_confianza.txt)                                                                                                             |
| 3   | El rol solo puede leer             | `aws iam list-attached-role-policies --role-name github-actions-terraform-plan`                                    | `AmazonEC2ReadOnlyAccess` y nada más                                                          | [03-rol_permisos.txt](03-rol_permisos.txt)                                                                                                                                 |
| 4   | El workflow corre los cuatro pasos | Push a `main` y revisar la pestaña **Actions**                                                                     | `fmt`, `init`, `validate` y `plan` en verde, con `Plan: 12 to add, 0 to change, 0 to destroy` | [04-terraform_workflow_verde.png](04-terraform_workflow_verde.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/39482796553/job/118847505330) |
| 5   | Diagnóstico del rechazo de AWS     | `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity` | Eventos `AccessDenied` con el `sub` real, y después uno sin error                             | [05-cloudtrail_sub_real.txt](05-cloudtrail_sub_real.txt)                                                                                                                   |

## Cómo reproducirlo

Con un usuario de AWS con permisos de IAM (no el que usa Terraform).

```powershell
# 1. Confiar en los tokens de GitHub Actions (una sola vez por cuenta)
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com
```
