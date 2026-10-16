# Paso 6: Autoescalado con HPA

Manifiesto: [hpa.yaml](../../k8s/hpa.yaml). Escala el Deployment `devops-pf-api` según el uso de CPU.

## Qué se automatizó

| Recurso                            | Qué hace                                                                               |
| ---------------------------------- | -------------------------------------------------------------------------------------- |
| `metrics-server` (v0.9.0)          | Recolecta el consumo real de CPU y memoria de cada pod y lo publica en la API de Kubernetes |
| `HorizontalPodAutoscaler` `devops-pf-api` | Ajusta el número de réplicas entre 1 y 3 para mantener la CPU promedio en 50% de los `requests` |

El HPA calcula, en cada ciclo (~15 s):

```
réplicas_deseadas = ceil( réplicas_actuales × utilización_actual% / objetivo% )
```

La utilización se mide sobre los **`requests`** del contenedor (50m de CPU), no sobre los `limits`. Por eso un pod que consume 25m está al 50%.

## Decisiones de diseño y FinOps

- **`minReplicas: 1`**: en reposo la aplicación consume ~15% de sus `requests`, así que un solo pod alcanza. Se prioriza el costo sobre la alta disponibilidad, que es aceptable en un entorno de pruebas. En producción convendría un mínimo de 2.
- **`maxReplicas: 3`**: techo de gasto. Con 178% de utilización el cálculo pedía 11 réplicas, y el límite lo mantuvo en 3, de modo que una ráfaga de tráfico no puede disparar el consumo del clúster.
- **`averageUtilization: 50`**: deja margen para absorber picos mientras se crean réplicas nuevas.
- **Subida rápida, bajada lenta**: el HPA sube en el siguiente ciclo, pero espera 5 minutos de uso bajo antes de reducir (`ScaleDownStabilized`). Evita oscilaciones.
- **`requests` coherentes**: el autoescalado solo funciona si los `requests` reflejan el consumo real de la aplicación (50m de CPU).

## Concesión de entorno local

En Docker Desktop, el kubelet usa un certificado sin la IP del nodo entre sus nombres válidos (*SAN*), y `metrics-server` lo rechazaba con `x509: cannot validate certificate ... doesn't contain any IP SANs`. El pod quedaba `Running` pero `0/1` (readiness 500: `no metrics to serve`). Se resolvió agregando el flag `--kubelet-insecure-tls`.

**Es válido solo para este entorno local.** En un clúster real se usan certificados válidos para los kubelets y no se desactiva la verificación TLS. Además, el cambio se hizo con `kubectl patch` (imperativo): si el clúster se recrea, hay que repetirlo (ver "Cómo reproducirlo").

## Validaciones

| #  | Qué se valida                                         | Comando                                                                 | Resultado esperado                                            | Evidencia                                                       |
| -- | ----------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------- |
| 1  | `metrics-server` disponible                           | `kubectl get deployment metrics-server -n kube-system`                  | `READY 1/1`                                                   | [01-metrics_server_deployment.txt](01-metrics_server_deployment.txt) |
| 2  | El flag `--kubelet-insecure-tls` quedó aplicado       | `kubectl get deployment metrics-server -n kube-system -o jsonpath=...`  | `--kubelet-insecure-tls` presente en `args`                   | [02-metrics_server_args.txt](02-metrics_server_args.txt)        |
| 3  | Métricas del nodo                                     | `kubectl top nodes`                                                     | CPU y memoria del nodo                                        | [03-top_nodes.txt](03-top_nodes.txt)                            |
| 4  | Métricas de los pods en reposo                        | `kubectl top pods -n devops-pf`                                         | Consumo de CPU de ~10m por pod                                | [04-top_pods_reposo.txt](04-top_pods_reposo.txt)                |
| 5  | El HPA se crea                                        | `kubectl apply -f k8s/hpa.yaml`                                         | `horizontalpodautoscaler ... created`                         | [05-hpa_apply.txt](05-hpa_apply.txt)                            |
| 6  | El HPA lee métricas en reposo                         | `kubectl get hpa -n devops-pf`                                          | `cpu: 18%/50%`, 2 réplicas                                    | [06-hpa_get_reposo.txt](06-hpa_get_reposo.txt)                  |
| 7  | Detalle del HPA en reposo                             | `kubectl describe hpa devops-pf-api -n devops-pf`                       | `ScalingActive: True`, `ValidMetricFound`                     | [07-hpa_describe.txt](07-hpa_describe.txt)                      |
| 8  | Reducción en reposo                                   | `kubectl get hpa -n devops-pf`                                          | 1 réplica tras la ventana de estabilización                   | [08-hpa_get_1_replica.txt](08-hpa_get_1_replica.txt)            |
| 9  | Escalado bajo carga                                   | `kubectl get hpa -n devops-pf`                                          | `cpu: 178%/50%`, 3 réplicas (tope)                            | [09-hpa_get_carga.txt](09-hpa_get_carga.txt)                    |
| 10 | Consumo por pod bajo carga                            | `kubectl top pods -n devops-pf`                                         | Pods de la API con ~80m (160% de los `requests`)              | [10-top_pods_carga.txt](10-top_pods_carga.txt)                  |
| 11 | Hay 3 pods de la API corriendo                        | `kubectl get pods -n devops-pf`                                         | 3 pods `devops-pf-api-*` en `Running`                         | [11-get_pods_3_replicas.txt](11-get_pods_3_replicas.txt)        |
| 12 | El HPA explica por qué escaló                         | `kubectl describe hpa devops-pf-api -n devops-pf`                       | Evento `SuccessfulRescale` y `ScalingLimited: TooManyReplicas` | [12-hpa_describe_carga.txt](12-hpa_describe_carga.txt)          |
| 13 | Vuelta a 1 réplica al cortar la carga                 | `kubectl get hpa -n devops-pf`                                          | `cpu: 14%/50%`, 1 réplica                                     | [13-hpa_get_post_carga.txt](13-hpa_get_post_carga.txt)          |
| 14 | Historial completo de escalado                        | `kubectl describe hpa devops-pf-api -n devops-pf`                       | Eventos: 1 → 3 → 2 → 1                                        | [14-hpa_describe_post_carga.txt](14-hpa_describe_post_carga.txt) |

## Cómo reproducirlo

```powershell
# 1. Instalar metrics-server con versión fija
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml

# 2. Solo entorno local (Docker Desktop): aceptar el certificado del kubelet
$patch = '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
$patch | Out-File "$env:TEMP\ms-patch.json" -Encoding ascii
kubectl patch deployment metrics-server -n kube-system --type=json --patch-file "$env:TEMP\ms-patch.json"
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s

# 3. Verificar métricas
kubectl top nodes
kubectl top pods -n devops-pf

# 4. Crear el HPA
kubectl apply -f k8s/hpa.yaml
kubectl get hpa -n devops-pf

# 5. Generar carga desde dentro del clúster
kubectl run carga -n devops-pf --image=busybox:1.36 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://devops-pf-api/ > /dev/null; done"

# 6. Observar el escalado (Ctrl+C para salir)
kubectl get hpa -n devops-pf -w

# 7. Cortar la carga y observar la reducción (tarda ~5 min por réplica)
kubectl delete pod carga -n devops-pf
```

## Interpretación del resultado

- En reposo el uso es ~15% y el HPA mantiene 1 réplica (`ceil(1 × 15/50) = 1`).
- Con la carga, los pods de la API pasaron de ~8m a ~80m de CPU (de ~16% a más del 150% de los `requests`). El HPA subió de 1 a 3 réplicas y quedó con `ScalingLimited: TooManyReplicas`: la demanda pedía más, pero el techo la
