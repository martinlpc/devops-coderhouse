# Paso 9: Despliegue en Kubernetes desde el pipeline

Job `deploy` de [ci.yml](../../.github/workflows/ci.yml), con la configuración del cluster en [.github/kind/cluster.yaml](../../.github/kind/cluster.yaml). Corre solo en push a `main`, después de que la imagen se publicó en GHCR.

## Qué se automatizó

| Paso                      | Qué hace                                                                          |
| ------------------------- | --------------------------------------------------------------------------------- |
| Crear cluster kind        | Levanta un cluster Kubernetes dentro de contenedores Docker, en el propio runner  |
| Instalar ingress-nginx    | El mismo controlador que se usa en local, versión fija `controller-v1.15.1`       |
| Instalar metrics-server   | v0.9.0 con `--kubelet-insecure-tls`, para que el HPA pueda medir CPU              |
| Apuntar a la imagen       | Reemplaza la imagen local del manifiesto por la que publicó `build-and-push`      |
| Desplegar los manifiestos | Aplica namespace, Deployment, Service, Ingress y HPA, con reintentos              |
| Verificar                 | Espera el 200 por el Ingress y que el HPA reporte CPU, y deja el estado en el log |

El cluster vive mientras dura el job y se destruye con él.

## Decisiones de diseño

- **kind en lugar de un cluster real**: un cluster en AWS por cada push costaría por hora y quedaría encendido entre ejecuciones. kind corre dentro de los minutos de runner que ya se consumen, así que el despliegue automático no agrega costo de infraestructura.
- **ingress-nginx y no Traefik**: es el mismo controlador que en Docker Desktop, así que los manifiestos del repositorio se aplican sin cambiarles el `ingressClassName`. El único valor que se reemplaza es la imagen.
- **La imagen se toma del job anterior**: `build-and-push` expone el tag como output del job (`steps.meta.outputs.version`), y `deploy` lo lee con `needs.build-and-push.outputs.image_tag`. Cada job corre en una máquina distinta, así que lo que se comparte entre ellos hay que declararlo.
- **El `sed` corre en el runner**: modifica la copia descartable del checkout, no el archivo del repositorio. `k8s/deployment.yaml` sigue apuntando a la imagen local, que es lo que sirve para desarrollo.
- **`curl -fsS`**: falla si la respuesta no es 2xx, así que el job se pone en rojo si la aplicación no responde. Sin `-f`, `curl` devolvería éxito aun con un 500.
- **Reintentos en lugar de esperas fijas**: tanto el `apply` como la verificación reintentan hasta que el componente recién arrancado está listo (ver "Incidentes").

## Los tres entornos del proyecto

| Tema           | Docker Desktop (local)        | k3s en AWS (paso 7)                     | kind en el pipeline         |
| -------------- | ----------------------------- | --------------------------------------- | --------------------------- |
| Para qué       | Desarrollo y pruebas manuales | Infraestructura real con Terraform      | Validar el despliegue en CI |
| Ingress        | ingress-nginx (`nginx`)       | Traefik (`traefik`)                     | ingress-nginx (`nginx`)     |
| Imagen         | Construida en local           | Descargada de GHCR                      | La que publicó el pipeline  |
| metrics-server | Se instala, con parche TLS    | Incluido en k3s, sin parche             | Se instala, con parche TLS  |
| Vida útil      | Permanente                    | Minutos, se destruye en la misma sesión | Lo que dura el job          |
| Costo          | Cero                          | USD 0,0134 medidos por 28 minutos       | Cero                        |

## FinOps

El despliegue automático no consume infraestructura paga. El job agrega alrededor de dos minutos de runner por push a `main`, y el `paths-ignore` del workflow evita que se dispare cuando solo cambian documentación o evidencias.

## Validaciones

| #   | Qué se valida                              | Comando / acción                                   | Resultado esperado                                                         | Evidencia                                                                                                                                             |
| --- | ------------------------------------------ | -------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Los tres jobs del pipeline en verde        | Push a `main` y revisar la pestaña **Actions**     | `test`, `build-and-push` y `deploy` encadenados y en verde                 | [01-pipeline_3_jobs_verdes.png](01-pipeline_3_jobs_verdes.png) y [ejecución](https://github.com/martinlpc/devops-coderhouse/actions/runs/39605328135) |
| 2   | Todos los pasos del deploy en verde        | Abrir el job `deploy`                              | Cluster creado, ingress y metrics-server instalados, manifiestos aplicados | [02-deploy_pasos_verdes.png](02-deploy_pasos_verdes.png)                                                                                              |
| 3   | Se despliega la imagen que publicó el CI   | Paso `Apuntar el Deployment a la imagen publicada` | `image: ghcr.io/martinlpc/devops-coderhouse:sha-<commit>`                  | [03-imagen_desplegada.txt](03-imagen_desplegada.txt)                                                                                                  |
| 4   | La app responde por el Ingress             | Paso `Verificar el despliegue`                     | `{"status":"ok"}` con 200, y el intento en que respondió                   | [04-verificacion_despliegue.txt](04-verificacion_despliegue.txt)                                                                                      |
| 5   | El HPA mide CPU en el cluster del pipeline | Mismo paso                                         | `cpu: 8%/50%`, 1 réplica, y `kubectl top` con 4m y 23Mi                    | [04-verificacion_despliegue.txt](04-verificacion_despliegue.txt)                                                                                      |

## Cómo reproducirlo

En local hace falta kind instalado y Docker corriendo.

```powershell
kind create cluster --name devops-pf --config .github/kind/cluster.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

# La imagen local no existe dentro de kind: se carga a mano
docker build -t devops-pf-api:1.0.0 ./app
kind load docker-image devops-pf-api:1.0.0 --name devops-pf

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
kubectl rollout status deployment/devops-pf-api -n devops-pf --timeout=180s
curl.exe -s -H "Host: devops-pf.local" http://localhost/health

kind delete cluster --name devops-pf
```

El pipeline no necesita `kind load` porque descarga la imagen de GHCR, que es pública.

## Incidentes resueltos durante la implementación

Los tres fallos tuvieron la misma raíz: dar por listo algo que acababa de arrancar.

1. **503 al verificar**. El pod ya estaba `Ready` y el Service tenía endpoints, pero ingress-nginx todavía no había recargado su configuración. Un 503 indica que encontró la regla del host y no tenía destino sano; si no hubiera encontrado la regla, la respuesta sería 404. Se resolvió reintentando el `curl` hasta 30 veces cada 2 segundos. En la ejecución final respondió en el tercer intento.

2. **El webhook de admisión rechazaba el Ingress**. ingress-nginx instala un `ValidatingWebhookConfiguration`: el API server le consulta al controlador antes de aceptar cualquier Ingress. El `apply` falló con `connection refused` contra el servicio de admisión. La sonda de readiness del controlador consulta su endpoint de salud (puerto 10254), que queda listo antes de que el listener del webhook acepte conexiones, así que el pod figura `Ready` sin que el webhook atienda. No hay una condición de Kubernetes que exprese eso, de modo que se reintenta el `apply`, que es idempotente.

3. **Bucles anidados en la verificación**. Al agregar la espera del HPA quedó un bucle dentro del otro: el `break` interno cortaba el de adentro, el externo giraba sus 30 vueltas y al terminar ejecutaba su rama de fallo. El job terminaba en rojo informando que la app no respondía, justo después de haber respondido 200 treinta veces. Se separaron en dos bucles consecutivos.

## Mejoras pendientes

- **Desplegar por digest**: hoy se usa el tag `sha-<commit>`, que es trazable al código pero sigue siendo una etiqueta y podría reescribirse. El digest (`@sha256:...`) identifica los bytes exactos de la imagen.
- **Prueba de carga en el pipeline**: el HPA se valida midiendo CPU en reposo. El escalado bajo carga está probado en el [paso 6](../06-hpa/), en local.
- **DAST**: este cluster queda listo para que OWASP ZAP ataque la aplicación ya desplegada, que es el paso siguiente.
