# Paso 12: FinOps

Optimización de costos aplicada en los tres planos donde el proyecto gasta: la infraestructura en AWS, los recursos del cluster y los minutos de ejecución del pipeline.

El costo total del proyecto en AWS fue de **0.044 USD**, de los cuales **0.0134 USD** son de infraestructura y **0.03 USD** son de las consultas a la API de Cost Explorer que se hicieron para medirla.

## El costo real

El único momento en que hubo infraestructura encendida fue el `apply` del paso 7: una instancia `t3.small` con k3s, durante 28 minutos, en `us-east-1`.

| Servicio                     | Costo (USD)   | Qué es                             |
| ---------------------------- | ------------- | ---------------------------------- |
| EC2 - Compute                | 0.0098511     | La instancia `t3.small` encendida  |
| Amazon Virtual Private Cloud | 0.0025097     | La dirección IPv4 pública asociada |
| EC2 - Other                  | 0.0010813     | El volumen `gp3` de 20 GB          |
| Amazon S3                    | 0.0000050     | Residual                           |
| AmazonCloudWatch             | 0             | Las dos alarmas de facturación     |
| **Subtotal infraestructura** | **0.0134472** |                                    |

El día siguiente al `destroy` el costo de estos servicios fue 0, lo cual confirma que no quedó nada encendido.

### El renglón inesperado

El desglose mensual de octubre muestra un servicio que no es parte de la arquitectura y que aun así encabeza la factura:

| Servicio             | Costo (USD) |
| -------------------- | ----------- |
| AWS Cost Explorer    | 0.03        |
| EC2 - Compute        | 0.01        |
| Resto de servicios   | 0.00        |
| **Total de octubre** | **~0.044**  |

La API de Cost Explorer cobra 0.01 USD por consulta. Las tres llamadas que se hicieron por CLI para obtener la evidencia en texto costaron más del doble que toda la infraestructura que estaban midiendo.

El dato no es una curiosidad: es el principio de FinOps aplicado a sí mismo. La observabilidad tiene costo propio, y ese costo hay que presupuestarlo igual que el del cómputo. Para un proyecto de este tamaño la diferencia son centavos; en una cuenta real, una consulta automatizada cada cinco minutos desde un panel son 0.01 USD cada vez, todo el día, todos los días.

La forma correcta de mirar el gasto en el día a día es la consola, que es gratuita, o un informe de uso y costo exportado a S3. La llamada por API se dejó documentada aquí a propósito, con su costo a la vista.

## Escalado automático

El HPA está configurado con mínimo 1 y máximo 3 réplicas, y objetivo del 50% de CPU sobre los `requests`. Los dos extremos importan: el mínimo en 1 evita pagar réplicas ociosas, y el máximo en 3 pone un techo a lo que el autoescalado puede llegar a consumir si algo se dispara.

El `deployment.yaml` no declara `replicas` a propósito. Si lo hiciera, cada `kubectl apply` pisaría el número que calculó el HPA y lo devolvería al valor del archivo.

El paso 11 muestra el ciclo completo medido: con carga el HPA sube de 1 a 3, y cuando la carga para registra `SuccessfulRescale ... New size: 2; reason: All metrics below target` y devuelve las réplicas. Escalar hacia abajo es la mitad del ahorro y suele ser la que se olvida.

## Límites de recursos

Cada pod de la aplicación declara `requests` de 50m de CPU y 64Mi de memoria, y `limits` de 200m y 128Mi.

Los `requests` son lo que el planificador reserva, y también la base sobre la que el HPA calcula el porcentaje. Los `limits` son el techo que el kernel impone. Sin `limits`, un pod con una fuga o un bucle puede consumir todo el nodo y arrastrar al resto.

Durante la prueba de carga del paso 11 esto se vio en vivo, por contraste: los pods de la aplicación nunca pasaron de sus límites y el nodo se mantuvo estable, mientras que el generador de carga, lanzado a mano y sin límites declarados, agotó las conexiones del nodo y tiró abajo el reenvío de puertos. El recurso protegido fue el que tenía límites.

## Apagado de recursos no usados

La infraestructura de AWS nunca quedó encendida entre sesiones. El ciclo fue `apply`, validar, capturar evidencia, `destroy`, y después verificar que no quedara nada:

- Instancias: `terminated`
- VPCs, volúmenes, IPs elásticas, NAT gateways y pares de claves: listas vacías

La verificación post-destroy importa más que el `destroy` en sí. Terraform informa lo que él cree que borró; consultar la API de AWS por separado confirma que no quedó un volumen huérfano o una IP elástica reservada, que son dos de las formas más comunes de seguir pagando por algo que se creía apagado.

En el cluster local vale la misma disciplina: al terminar cada sesión de trabajo se baja el monitoreo y la aplicación con `kubectl delete namespace monitoring devops-pf`.

## Barreras de gasto

Dos alarmas de CloudWatch sobre la métrica de facturación estimada, cada una con su tema de SNS:

| Alarma                              | Umbral | Estado |
| ----------------------------------- | ------ | ------ |
| Alerta Gasto Mayor a 5 USD          | 5 USD  | OK     |
| Alerta gasto mayor o igual a 20 USD | 20 USD | OK     |

La de 5 USD es el presupuesto que se fijó para todo el proyecto; la de 20 es la red de contención por si algo se escapa.

Hay una tercera barrera que no es una alarma sino un límite estructural: el usuario `terraform-pf` con el que corre Terraform tiene únicamente la política `AmazonEC2FullAccess`. Eso le alcanza para crear la red y la instancia, y no le alcanza para crear un cluster EKS, que cuesta 0.10 USD por hora solo por el plano de control, más de siete veces lo que salió todo el proyecto. Un permiso que no existe es un gasto que no puede ocurrir.

## Imputación de costos

Todos los recursos llevan las etiquetas `Project` y `ManagedBy`, aplicadas de una sola vez con el bloque `default_tags` del proveedor de AWS en lugar de repetirlas recurso por recurso.

La etiqueta `Project` está activada como etiqueta de asignación de costos, lo cual permite filtrar el gasto por proyecto en Cost Explorer. La activación no es retroactiva: solo aplica desde el momento en que se habilita, por eso conviene hacerlo antes de crear infraestructura y no después.

Las mismas etiquetas sirvieron para la verificación post-destroy, que filtra por `Name=tag:Project,Values=devops-pf`.

## Minutos de pipeline

Los dos workflows están filtrados para no ejecutarse de más, porque cada corrida consume minutos del plan de GitHub Actions:

| Workflow                                               | Filtro                                                    |
| ------------------------------------------------------ | --------------------------------------------------------- |
| [ci.yml](../../.github/workflows/ci.yml)               | `paths-ignore` sobre `evidencias/**` y `**.md`            |
| [terraform.yml](../../.github/workflows/terraform.yml) | `paths` restringido a `terraform/**` y al propio workflow |

Sin esos filtros, cada commit de documentación dispararía una construcción de imagen, un despliegue en un cluster `kind` y un escaneo de ZAP completos. Solo en este proyecto hubo varios commits de documentación seguidos que no construyeron nada.

El workflow de Terraform llega hasta `plan` y nunca ejecuta `apply`, y el rol que asume por OIDC tiene `AmazonEC2ReadOnlyAccess`. El pipeline puede decir qué cambiaría, no puede crear nada que cueste dinero.

## Validaciones

| #   | Qué se valida                           | Evidencia                                                                                                    |
| --- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| 1   | El costo real del proyecto              | [01-costo_real_apply.txt](01-costo_real_apply.txt)                                                           |
| 2   | La etiqueta de imputación está activa   | [02-tag_asignacion_costos.png](02-tag_asignacion_costos.png)                                                 |
| 3   | Las alarmas de facturación existen      | [../07-terraform/12-alarmas_facturacion.txt](../07-terraform/12-alarmas_facturacion.txt)                     |
| 4   | Los recursos quedan etiquetados         | [../07-terraform/20-aws_instancia_tags.txt](../07-terraform/20-aws_instancia_tags.txt)                       |
| 5   | La infraestructura se destruye          | [../07-terraform/21-terraform_destroy.txt](../07-terraform/21-terraform_destroy.txt)                         |
| 6   | No queda nada encendido después         | [../07-terraform/22-aws_verificacion_post_destroy.txt](../07-terraform/22-aws_verificacion_post_destroy.txt) |
| 7   | El permiso de Terraform es acotado      | [../07-terraform/03-iam_policy_terraform-pf.txt](../07-terraform/03-iam_policy_terraform-pf.txt)             |
| 8   | El HPA sube y baja según la carga       | [../11-monitoreo/09-hpa_durante_carga.txt](../11-monitoreo/09-hpa_durante_carga.txt)                         |
| 9   | El HPA respeta el mínimo y el máximo    | [../06-hpa/](../06-hpa/)                                                                                     |
| 10  | El costo mensual total, con su desglose | [03-costo_total_mes.png](03-costo_total_mes.png)                                                             |

## Mejoras pendientes

- **AWS Budgets en lugar de alarmas de CloudWatch**: Budgets permite presupuestos por etiqueta y pronóstico de gasto a fin de mes, cosas que una alarma sobre la métrica de facturación no hace.
- **Instancias Spot** para cargas tolerantes a interrupción, con descuentos de hasta el 90% sobre el precio bajo demanda.
- **Políticas de ciclo de vida en el registro de imágenes**: hoy cada push publica una imagen nueva etiquetada por SHA y ninguna se borra nunca.
- **Caché de dependencias en el pipeline**: ya está para pnpm, falta para las capas de Docker, que es donde se va la mayor parte del tiempo de construcción.
- **Reemplazar las consultas a la API de Cost Explorer** por la consola o por un informe de uso y costo (CUR) exportado a S3, que no cobra por consulta.
