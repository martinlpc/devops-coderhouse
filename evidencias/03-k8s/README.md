# Paso 3: Kubernetes local

Cluster: Kubernetes integrado en Docker Desktop (contexto `docker-desktop`, 1 nodo).

## Qué se desplegó

| Objeto     | Archivo                                      | Función                                                                                   |
| ---------- | -------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Namespace  | [namespace.yaml](../../k8s/namespace.yaml)   | Aísla los recursos del proyecto                                                           |
| Deployment | [deployment.yaml](../../k8s/deployment.yaml) | 2 réplicas de la API, probes sobre `/health`, requests/limits y `securityContext` no root |
| Service    | [service.yaml](../../k8s/service.yaml)       | `ClusterIP` en el puerto 80 que reenvía al 3000 de los Pods                               |

## Validaciones

| #   | Qué se valida                                    | Comando                                                                            | Resultado esperado                                                              | Evidencia                                            |
| --- | ------------------------------------------------ | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------- |
| 1   | Existe el contexto del cluster                   | `kubectl config get-contexts`                                                      | Aparece `docker-desktop`                                                        | [01-contexts.txt](01-contexts.txt)                   |
| 2   | El nodo está listo                               | `kubectl get nodes`                                                                | Estado `Ready`                                                                  | [02-nodes.txt](02-nodes.txt)                         |
| 3   | Los pods están listos                            | `kubectl get pods `                                                                | Log `Escuchando en puerto 3000` por cada réplica                                | [03-pods.txt](02-pods.txt)                           |
| 4   | El Deployment se despliega por completo          | `kubectl rollout status deployment/devops-pf-api -n devops-pf`                     | `successfully rolled out`                                                       | [04-rollout.txt](04-rollout.txt)                     |
| 5   | Las 2 réplicas arrancaron la app                 | `kubectl logs -n devops-pf -l app=devops-pf-api --prefix`                          | Un log `Escuchando en puerto 3000` por cada Pod (2)                             | [05-logs.txt](05-logs.txt)                           |
| 6   | El Deployment tiene la configuración declarada   | `kubectl describe deployment devops-pf-api -n devops-pf`                           | 2 réplicas, probes sobre `/health`, requests/limits y `securityContext` no root | [06-describe.txt](06-describe.txt)                   |
| 7   | El Service existe y es interno                   | `kubectl get svc -n devops-pf`                                                     | Tipo `ClusterIP`, puerto `80/TCP`                                               | [07-svc.txt](07-svc.txt)                             |
| 8   | El Service apunta a los 2 Pods                   | `kubectl get endpoints -n devops-pf`                                               | 2 IPs con puerto 3000 (no `<none>`)                                             | [08-endpoints.txt](08-endpoints.txt)                 |
| 9   | La API responde a través del Service             | `curl.exe -i localhost:8080/health` (con `port-forward` activo)                    | `200 OK` con `{"status":"ok"}`                                                  | [09-curl_health.txt](09-curl_health.txt)             |
| 10  | Las métricas son accesibles a través del Service | `curl.exe -s localhost:8080/metrics` (con `port-forward` activo)                   | Formato Prometheus                                                              | [10-curl_metrics.txt](10-curl_metrics.txt)           |
| 11  | Un Pod borrado se repone solo                    | `kubectl delete pod <nombre> -n devops-pf` y luego `kubectl get pods -n devops-pf` | Aparece un Pod nuevo y vuelve a haber 2 en `Running`                            | [11-pod_recreado.txt](11-pod_recreado.txt)           |
| 12  | El Service actualiza sus destinos                | `kubectl get endpoints -n devops-pf` (después de borrar el Pod)                    | 2 IPs, una distinta a la de antes                                               | [12-endpoints_despues.txt](12-endpoints_despues.txt) |

## Conclusión de la prueba de autorreparación

Al borrar el Pod `devops-pf-api-dd7cd6d-6lxdp` (IP `10.1.0.8:3000`), el Deployment creó `devops-pf-api-dd7cd6d-fcdhx` (IP `10.1.0.9:3000`) y el Service actualizó sus endpoints sin intervención manual. Se compara [08-endpoints.txt](08-endpoints.txt) (antes) con [12-endpoints-despues.txt](12-endpoints-despues.txt) (después).

## Cómo reproducirlo

    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl get pods,svc,endpoints -n devops-pf
    kubectl port-forward -n devops-pf svc/devops-pf-api 8080:80
