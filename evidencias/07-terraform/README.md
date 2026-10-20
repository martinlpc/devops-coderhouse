# Paso 7: Infraestructura con Terraform en AWS

Código en [terraform/](../../terraform/). Crea una red, una instancia EC2 y un cluster Kubernetes (k3s) en AWS, y despliega la aplicación en él. La infraestructura se creó, se verificó y se destruyó en una sola sesión de unos 30 minutos.

## Qué se automatizó

| Módulo / archivo           | Qué hace                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------ |
| `modules/network`          | VPC, subred pública, internet gateway, route table y security group con sus reglas                     |
| `modules/compute`          | Clave SSH, instancia EC2 `t3.small` (Ubuntu 24.04) y script `user_data.sh` que instala k3s al arrancar |
| `main.tf` / `variables.tf` | Provider `hashicorp/aws ~> 6.0`, etiquetas por defecto y llamada a los dos módulos                     |
| `outputs.tf`               | IP pública y comando SSH                                                                               |

Total: 12 recursos. La búsqueda de la AMI es un data source y no crea nada.

## Decisiones de diseño y FinOps

- Cuenta real de AWS, ventana corta y `terraform destroy` al final. Costo estimado: unos 0,03 USD por hora con precios de lista de `us-east-1` (`t3.small` + IPv4 pública + disco de 20 GB), a verificar en Cost Explorer.
- Sin NAT gateway (0,045 USD por hora más tráfico): la instancia vive en una subred pública y el firewall limita lo que entra.
- k3s en lugar de EKS: el plano de control de EKS cuesta por sí solo ~0,10 USD por hora.
- Mínimo privilegio: Terraform corre con un usuario IAM propio (`terraform-pf`) que solo tiene `AmazonEC2FullAccess`. No puede crear clusters EKS ni tocar IAM.
- Alarmas de facturación en 5 y 20 USD con aviso por mail (región `us-east-1`). Avisan, no cortan el gasto.
- Etiquetas `Project` y `ManagedBy` en todos los recursos (`default_tags`), para filtrar costos por proyecto.
- El `apply` es manual y acotado. El pipeline solo hará `fmt`, `validate` y `plan`.

## Seguridad

- Security group: SSH (22) y API de Kubernetes (6443) solo desde `allowed_cidr` (la IP del operador, variable sin valor por defecto). Solo el puerto 80 está abierto a internet.
- La regla de salida es explícita: Terraform elimina la que AWS crea por defecto, y sin ella la instancia no podría descargar k3s.
- IMDSv2 obligatorio (`http_tokens = "required"`).
- k3s se instala con `--tls-san <ip pública>` para que `kubectl` remoto valide el certificado de la API sin desactivar la verificación TLS.
- El state, `.terraform/`, `*.tfvars` y los planes guardados están en `.gitignore`. Se versiona `.terraform.lock.hcl` y una plantilla `terraform.tfvars.example`.
- Las IP y el número de cuenta de las evidencias están enmascarados.

## Diferencias entre k3s y el cluster local

| Tema           | Docker Desktop (local)                         | k3s en AWS                                                         |
| -------------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| Ingress        | `ingress-nginx` (`ingressClassName: nginx`)    | Traefik, incluido en k3s (`ingressClassName: traefik`)             |
| Imagen         | Construida en local (`devops-pf-api:1.0.0`)    | Descargada de GHCR (`ghcr.io/martinlpc/devops-coderhouse:sha-...`) |
| metrics-server | Se instala y requiere `--kubelet-insecure-tls` | Viene incluido y funciona sin parche                               |

Para no tocar los manifiestos del repo, el despliegue en k3s se hizo sobre una copia temporal de `k8s/` con esos dos valores reemplazados.

## Límites conocidos

- State local, sin bloqueo. En un equipo se usaría un backend remoto (S3 con bloqueo).
- Un solo nodo: no hay alta disponibilidad. Con 1158 Mi de memoria usados (60%) en una `t3.small`, el nodo no tiene lugar para Prometheus y Grafana, que se despliegan en el cluster del pipeline.
- La versión de k3s sigue el canal `stable`. En producción se fijaría una versión exacta.
- La IP pública cambia en cada creación y `allowed_cidr` hay que actualizarlo si cambia la IP del operador.

## Validaciones

| #   | Qué se valida                          | Comando                                                         | Resultado esperado                                           | Evidencia                                                                    |
| --- | -------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| 1   | Terraform instalado                    | `terraform version`                                             | v1.16.6                                                      | [01-terraform_version.txt](01-terraform_version.txt)                         |
| 2   | AWS CLI instalado                      | `aws --version`                                                 | aws-cli 2.x                                                  | [02-aws_cli_version.txt](02-aws_cli_version.txt)                             |
| 3   | El usuario del proyecto solo tiene EC2 | `aws iam list-attached-user-policies --user-name terraform-pf`  | `AmazonEC2FullAccess`                                        | [03-iam_policy_terraform-pf.txt](03-iam_policy_terraform-pf.txt)             |
| 4   | Identidad con la que corre Terraform   | `aws sts get-caller-identity --profile terraform-pf`            | `user/terraform-pf`                                          | [04-sts_terraform-pf.txt](04-sts_terraform-pf.txt)                           |
| 5   | Mínimo privilegio                      | `aws iam list-users --profile terraform-pf`                     | `AccessDenied`                                               | [05-iam_list-users_denegado.txt](05-iam_list-users_denegado.txt)             |
| 6   | State y `tfvars` fuera de git          | `git check-ignore -v ...`                                       | Reglas de `.gitignore`; el `.example` no se ignora           | [06-gitignore_check.txt](06-gitignore_check.txt)                             |
| 7   | Provider descargado                    | `terraform init`                                                | `hashicorp/aws v6.69.1`                                      | [07-terraform_init.txt](07-terraform_init.txt)                               |
| 8   | Módulo de red válido                   | `terraform validate`                                            | `Success! The configuration is valid.`                       | [08-terraform_validate.txt](08-terraform_validate.txt)                       |
| 9   | Plan de la red                         | `terraform plan`                                                | `Plan: 10 to add`                                            | [09-terraform_plan_network.txt](09-terraform_plan_network.txt)               |
| 10  | Configuración completa válida          | `terraform validate`                                            | `Success! The configuration is valid.`                       | [10-terraform_validate_completo.txt](10-terraform_validate_completo.txt)     |
| 11  | Plan completo                          | `terraform plan`                                                | `Plan: 12 to add`                                            | [11-terraform_plan_completo.txt](11-terraform_plan_completo.txt)             |
| 12  | Alarmas de facturación activas         | `aws cloudwatch describe-alarms ...`                            | Umbrales de 5 y 20 USD, estado `OK`, con topic SNS           | [12-alarmas_facturacion.txt](12-alarmas_facturacion.txt)                     |
| 13  | Creación de la infraestructura         | `terraform apply tfplan`                                        | `Resources: 12 added`                                        | [13-terraform_apply.txt](13-terraform_apply.txt)                             |
| 14  | k3s instalado por `user_data`          | `ssh ... kubectl get nodes; kubectl get pods -A`                | Nodo `Ready`; Traefik, CoreDNS y metrics-server en `Running` | [14-k3s_nodos_pods.txt](14-k3s_nodos_pods.txt)                               |
| 15  | La app responde desde internet         | `curl -H "Host: devops-pf.local" http://<ip>/health`            | `HTTP 200`                                                   | [15-k3s_curl_health.txt](15-k3s_curl_health.txt)                             |
| 16  | El Ingress enruta por host             | `curl http://<ip>/`                                             | `404` (sin cabecera `Host`)                                  | [16-k3s_curl_sin_host.txt](16-k3s_curl_sin_host.txt)                         |
| 17  | Recursos de la app en k3s              | `kubectl get pods,svc,ingress,hpa -n devops-pf`                 | Pod `Running`, Ingress `traefik`, HPA con CPU medida         | [17-k3s_recursos_app.txt](17-k3s_recursos_app.txt)                           |
| 18  | metrics-server sin parche              | `kubectl top nodes; kubectl top pods -n devops-pf`              | Métricas de nodo y pod                                       | [18-k3s_top.txt](18-k3s_top.txt)                                             |
| 19  | Recursos que gestiona Terraform        | `terraform state list`                                          | 12 recursos y 1 data source                                  | [19-terraform_state_list.txt](19-terraform_state_list.txt)                   |
| 20  | Etiquetas de costos                    | `aws ec2 describe-instances --filters Name=tag:Project,...`     | `t3.small` con `Project=devops-pf`                           | [20-aws_instancia_tags.txt](20-aws_instancia_tags.txt)                       |
| 21  | Destrucción                            | `terraform apply destroy.tfplan`                                | `12 destroyed`                                               | [21-terraform_destroy.txt](21-terraform_destroy.txt)                         |
| 22  | No queda nada facturando               | `aws ec2 describe-instances / vpcs / volumes / addresses / ...` | Instancia `terminated`; el resto `[]`                        | [22-aws_verificacion_post_destroy.txt](22-aws_verificacion_post_destroy.txt) |

## Cómo reproducirlo

Requisitos: Terraform >= 1.9, AWS CLI, un usuario IAM con `AmazonEC2FullAccess` configurado como perfil `terraform-pf`, y un par de claves SSH.

```powershell
# 1. Clave SSH (la privada no se sube al repo)
ssh-keygen -t ed25519 -f "$HOME\.ssh\devops-pf" -C "devops-pf"

# 2. Variables: IP autorizada para SSH y API de Kubernetes
cd terraform
$ip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
"allowed_cidr = `"$ip/32`"" | Out-File -Encoding ascii terraform.tfvars

# 3. Inicializar, validar y planificar
terraform init
terraform validate
terraform plan "-out=tfplan"

# 4. Crear (12 recursos). Esperar ~3 minutos a que k3s termine de instalarse
terraform apply tfplan

# 5. Comprobar el cluster por SSH
$ip = terraform output -raw public_ip
ssh -i $HOME\.ssh\devops-pf ubuntu@$ip "cloud-init status --wait; sudo k3s kubectl get nodes"

# 6. Usar kubectl desde la máquina local
$kc = "$HOME\.kube\k3s-devops-pf.yaml"
ssh -i $HOME\.ssh\devops-pf ubuntu@$ip "sudo cat /etc/rancher/k3s/k3s.yaml" | ForEach-Object { $_ -replace '127.0.0.1',$ip } | Out-File -Encoding ascii $kc
$env:KUBECONFIG = $kc
kubectl get nodes

# 7. Desplegar la app sobre una copia de k8s/ adaptada a k3s
cd ..
$tmp = "$env:TEMP\k8s-k3s"
Copy-Item k8s $tmp -Recurse
(Get-Content $tmp\ingress.yaml) -replace 'ingressClassName: nginx','ingressClassName: traefik' | Set-Content $tmp\ingress.yaml
(Get-Content $tmp\deployment.yaml) -replace 'image: devops-pf-api:1.0.0','image: ghcr.io/martinlpc/devops-coderhouse:sha-<7 caracteres>' | Set-Content $tmp\deployment.yaml
kubectl apply -f $tmp\namespace.yaml
kubectl apply -f $tmp
curl.exe -i -H "Host: devops-pf.local" http://$ip/health

# 8. Destruir todo y verificar
Remove-Item Env:KUBECONFIG
terraform -chdir=terraform plan -destroy "-out=destroy.tfplan"
terraform -chdir=terraform apply destroy.tfplan
```
