# Paso 11: Monitoreo con Prometheus y Grafana

Monitoreo desplegado sobre el cluster local de Docker Desktop, con manifiestos propios en [k8s/monitoring/](../../k8s/monitoring/) en lugar de un chart de Helm. La decisión fue deliberada: el `prometheus.yml` y el dashboard quedan escritos en el repositorio y se pueden leer, y el conjunto son dos pods contra los nueve de `kube-prometheus-stack`.

Corre en local y no en el pipeline porque el cluster `kind` del runner vive unos minutos y se destruye: no hay forma de abrir Grafana ni de capturar un dashboard. La consigna pide monitoreo como punto aparte de los seis que sí se automatizan en el pipeline.

## Qué se desplegó

| Archivo                                                                     | Objetos                                          | Para qué                                                   |
| --------------------------------------------------------------------------- | ------------------------------------------------ | ---------------------------------------------------------- |
| [00-namespace.yaml](../../k8s/monitoring/00-namespace.yaml)                 | Namespace `monitoring`                           | Aísla el monitoreo de la aplicación                        |
| [01-rbac.yaml](../../k8s/monitoring/01-rbac.yaml)                           | ServiceAccount, Role, RoleBinding                | Permite a Prometheus listar pods, solo en `devops-pf`      |
| [02-prometheus-config.yaml](../../k8s/monitoring/02-prometheus-config.yaml) | ConfigMap                                        | El `prometheus.yml` con el descubrimiento y los relabels   |
| [03-prometheus.yaml](../../k8s/monitoring/03-prometheus.yaml)               | Deployment y Service (`prom/prometheus:v3.15.1`) | Recolecta y almacena las métricas                          |
| [04-grafana-config.yaml](../../k8s/monitoring/04-grafana-config.yaml)       | Tres ConfigMaps                                  | Datasource, proveedor de dashboards y el dashboard en JSON |
| [05-grafana.yaml](../../k8s/monitoring/05-grafana.yaml)                     | Deployment y Service (`grafana/grafana:13.2.3`)  | Visualiza las métricas                                     |

La clave de administrador de Grafana no está en el repositorio. Se crea a mano con `kubectl create secret`, y el Deployment la lee con `secretKeyRef`.

## Cómo Prometheus encuentra la aplicación

Prometheus no recibe métricas, las va a buscar cada 15 segundos. Para saber a quién, le pregunta a la API de Kubernetes con `kubernetes_sd_configs` usando `role: pod`, acotado al namespace `devops-pf`.

El descubrimiento no devuelve objetivos listos, devuelve candidatos con metadata en etiquetas que empiezan con `__meta_`. Los `relabel_configs` son la cadena que los filtra y los transforma antes del scrape:

| Regla                                         | Acción    | Para qué                                                            |
| --------------------------------------------- | --------- | ------------------------------------------------------------------- |
| `__meta_kubernetes_pod_label_app`             | `keep`    | Solo los pods de la aplicación, no todo lo que viva en el namespace |
| `__meta_kubernetes_pod_container_port_number` | `keep`    | Solo el puerto 3000, por si el pod declarara más de uno             |
| `__meta_kubernetes_pod_name` → `pod`          | reemplazo | Deja el nombre del pod como etiqueta consultable                    |

Esa última regla es la que hace que el dashboard pueda separar las series por réplica. Cuando el HPA escala a tres pods, `watch` le avisa a Prometheus y los tres aparecen como objetivos distintos, cada uno con su etiqueta `pod`.

Prometheus scrapea la IP del pod directamente, no pasa por el Service ni por el Ingress. Si fuera por el Service, el balanceo haría caer cada scrape en una réplica distinta y los contadores saldrían en zigzag.

## Por qué un Role y no un ClusterRole

Casi todos los ejemplos de Prometheus usan un `ClusterRole`, porque descubren pods en todo el cluster. Acá el descubrimiento está acotado a un namespace, y cuando se fijan los namespaces Prometheus hace llamadas acotadas a la API en lugar de listar todo, de modo que alcanza un `Role`.

El resultado es que el ServiceAccount puede listar pods en `devops-pf` y en ningún otro lado, lo cual se verifica explícitamente en las validaciones 2 y 3. Mismo criterio que el usuario `terraform-pf` del paso 7 y el rol de solo lectura del paso 8.

El RoleBinding vive en `devops-pf`, donde está el Role, y apunta a un ServiceAccount de `monitoring`. Un binding puede referenciar sujetos de otro namespace, por eso el sujeto lleva su propio campo `namespace` y el `roleRef` no.

## El dashboard

Se provisiona desde un ConfigMap, no se arma clickeando en la interfaz: el JSON queda versionado en el repositorio y Grafana lo levanta solo al arrancar.

| Panel               | Consulta                                                        |
| ------------------- | --------------------------------------------------------------- |
| Replicas scrapeadas | `sum(up{job="devops-pf-api"})`                                  |
| Uptime del proceso  | `max(time() - process_start_time_seconds{job="devops-pf-api"})` |
| CPU por pod (cores) | `rate(process_cpu_seconds_total{job="devops-pf-api"}[1m])`      |
| Memoria RSS por pod | `process_resident_memory_bytes{job="devops-pf-api"}`            |
| Heap usado por pod  | `nodejs_heap_size_used_bytes{job="devops-pf-api"}`              |
| Event loop lag p99  | `nodejs_eventloop_lag_p99_seconds{job="devops-pf-api"}`         |

Las métricas vienen de `collectDefaultMetrics()` de `prom-client`, que la aplicación expone en `/metrics` desde el paso 1.

## Hallazgos

**Grafana no arrancaba con 256Mi de límite.** Con ese límite el contenedor no llegaba a escuchar en el puerto 3000 y el port-forward devolvía `connection refused` dentro del namespace del pod. Se subió el límite a 512Mi y se deshabilitó el instalador de plugins en segundo plano con `GF_PLUGINS_PREINSTALL_DISABLED`. Con las dos correcciones el arranque pasó a ser de segundos.

Ese instalador merece mención aparte: Grafana 13 sale a internet en cada arranque a actualizar plugins que vienen con la imagen (jaeger, elasticsearch, zipkin, postgresql), ninguno de los cuales usamos. Deshabilitarlo hace el arranque determinista y elimina la dependencia de tener conexión.

**La imagen de Grafana son 482MB y tardó 8m42s en bajar.** Los `rollout status` con 120 segundos de timeout fallan en el primer despliegue aunque el pod esté perfectamente sano.

**El generador de carga tumbó el port-forward, la aplicación no.** Dos generadores con `wget` en bucle cerrado sin pausa abrían miles de conexiones TCP por segundo, y el port-forward empezó a fallar al crear streams nuevos (`error creating error stream: Timeout occurred`) mientras el nodo estaba al 9% de CPU. No fue saturación de cómputo sino agotamiento de conexiones. Se resolvió con un solo generador y una pausa de 20ms entre pedidos.

El contraste es el punto: los pods de la aplicación tienen `requests` y `limits` declarados y nunca pudieron desestabilizar nada, mientras que el generador lanzado a mano sin límites sí lo hizo. Es el argumento concreto de por qué los límites están en los manifiestos.

**El event loop lag p99 pasó de 10ms en reposo a 180ms bajo carga.** Es la señal que `kubectl top` no da: el CPU puede estar lejos del límite mientras el bucle de eventos de Node ya se está llenando y la latencia percibida sube.

**`/metrics` queda expuesto por el Ingress.** El Ingress enruta todo `/` a la aplicación, así que las métricas son públicas para quien alcance el host. No se cerró con una anotación de nginx porque `server-snippet` viene deshabilitado por defecto en ingress-nginx desde la 1.9 y habilitarlo exige tocar la configuración del controlador. El dato que respalda la decisión: Prometheus scrapea la IP del pod en el puerto 3000 y no pasa por el Ingress, de modo que bloquear `/metrics` ahí no rompería el monitoreo. Queda como mejora pendiente, no como dependencia.

## Validaciones

| #   | Qué se valida                             | Comando / acción                                       | Resultado esperado                                            | Evidencia                                                        |
| --- | ----------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------- | ---------------------------------------------------------------- |
| 1   | El HPA escala por CPU de forma autónoma   | `kubectl get events -n devops-pf`                      | `SuccessfulRescale ... above target`                          | [01-hpa_escalado_real.txt](01-hpa_escalado_real.txt)             |
| 2   | Los objetos del monitoreo están corriendo | `kubectl get all,configmap,secret -n monitoring`       | Dos Deployments `1/1`, cuatro ConfigMaps propios y el Secret  | [02-objetos_monitoring.txt](02-objetos_monitoring.txt)           |
| 3   | El permiso existe donde tiene que existir | `kubectl auth can-i list pods -n devops-pf --as=...`   | `yes`                                                         | [03-rbac_least_privilege.txt](03-rbac_least_privilege.txt)       |
| 4   | El permiso no existe fuera de ahí         | `kubectl auth can-i list pods -n kube-system --as=...` | `no`                                                          | [03-rbac_least_privilege.txt](03-rbac_least_privilege.txt)       |
| 5   | Prometheus descubre la aplicación         | `GET /api/v1/targets?state=active`                     | Dos jobs en `up`, con la etiqueta `pod` poblada               | [04-prometheus_targets.txt](04-prometheus_targets.txt)           |
| 6   | Las métricas se pueden consultar          | `GET /api/v1/query?query=up{job="devops-pf-api"}`      | `"status": "success"` con un resultado por réplica            | [05-query_up.json](05-query_up.json)                             |
| 7   | El objetivo aparece en la interfaz        | `http://localhost:9090/targets`                        | Job en UP con las tres etiquetas visibles                     | [06-prometheus_targets.png](06-prometheus_targets.png)           |
| 8   | El dashboard se provisiona con datos      | `http://localhost:3001`                                | Seis paneles con series, sin intervención manual              | [07-grafana_dashboard.png](07-grafana_dashboard.png)             |
| 9   | El monitoreo refleja el autoescalado      | Dashboard durante la prueba de carga                   | Tres series por panel y el contador de réplicas en 3          | [08-grafana_dashboard_carga.png](08-grafana_dashboard_carga.png) |
| 10  | El HPA sube y baja según la carga         | Muestreo de `kubectl get hpa` cada 5s                  | 21% → 69% → escala a 3 → 49% → 40%, y `New size: 2` al cortar | [09-hpa_durante_carga.txt](09-hpa_durante_carga.txt)             |

## Cómo reproducirlo

Requiere Docker Desktop con Kubernetes habilitado. Al elegir el método de aprovisionamiento conviene **kubeadm** y no kind: con kind el nodo tiene su propio containerd y las imágenes construidas con `docker build` no le llegan sin un paso extra de importación.

```powershell
kubectl config use-context docker-desktop
```

metrics-server, necesario para el HPA:

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
$patch = '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl patch deployment metrics-server -n kube-system --type=json -p $patch
```

La aplicación, usando la imagen que publicó el pipeline:

```powershell
$img = "ghcr.io/martinlpc/devops-coderhouse:sha-6edfa99"
$text = (Get-Content k8s\deployment.yaml -Raw) -replace 'image: devops-pf-api:1\.0\.0', "image: $img"
$tmp = Join-Path $env:TEMP "deployment-local.yaml"
[System.IO.File]::WriteAllText($tmp, $text, (New-Object System.Text.UTF8Encoding $false))

kubectl apply -f k8s\namespace.yaml
kubectl apply -f k8s\service.yaml -f k8s\ingress.yaml -f k8s\hpa.yaml
kubectl apply -f $tmp
```

El monitoreo:

```powershell
kubectl apply -f k8s\monitoring\
kubectl create secret generic grafana-admin -n monitoring --from-literal=password='<clave-local>'
kubectl rollout status deployment/prometheus -n monitoring --timeout=300s
kubectl rollout status deployment/grafana -n monitoring --timeout=600s
```

Dos ventanas con los reenvíos de puerto:

```powershell
kubectl port-forward -n monitoring svc/prometheus 9090:9090
kubectl port-forward -n monitoring svc/grafana 3001:3000
```

Prometheus en `http://localhost:9090/targets`, Grafana en `http://localhost:3001` con usuario `admin`.

La prueba de carga, con pausa para no agotar las conexiones del nodo:

```powershell
kubectl run carga --rm -i --image=busybox:1.37 -n devops-pf --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://devops-pf-api.devops-pf.svc.cluster.local/ >/dev/null; sleep 0.02; done"
```

Al terminar, para no dejar nada consumiendo recursos:

```powershell
kubectl delete namespace monitoring devops-pf
```

## Mejoras pendientes

- **Cerrar `/metrics` en el Ingress**, habilitando `allow-snippet-annotations` en el controlador o moviendo las métricas a un puerto aparte que el Ingress no publique.
- **Métricas de HTTP**: `collectDefaultMetrics()` da CPU, memoria y bucle de eventos, pero no pedidos por segundo, latencia ni tasa de error. Un middleware con un contador y un histograma agregaría los tres paneles que hoy faltan.
- **Alertas**: Prometheus está desplegado sin reglas ni Alertmanager. Una regla sobre `up == 0` o sobre el event loop lag sería el paso natural.
- **Persistencia**: la retención está en dos horas sobre un `emptyDir`, a propósito para un entorno de demostración. Un entorno real necesita un PersistentVolume.
