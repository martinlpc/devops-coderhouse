# Paso 3: Kubernetes local

Cluster: Kubernetes integrado en Docker Desktop (contexto `docker-desktop`, 1 nodo).

## Qué se desplegó

| Objeto     | Archivo                                      | Función                                                                                                           |
| ---------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Namespace  | [namespace.yaml](../../k8s/namespace.yaml)   | Aísla los recursos del proyecto                                                                                   |
| Deployment | [deployment.yaml](../../k8s/deployment.yaml) | 2 réplicas de la API, probes sobre `/health`, requests/limits y `securityContext` no root                         |
| Service    | [service.yaml](../../k8s/service.yaml)       | `ClusterIP` en el puerto 80 que reenvía al 3000 de los Pods                                                       |
| Ingress    | [ingress.yaml](../../k8s/ingress.yaml)       | Manifiesto de reglas de enrutamiento consumido por NGINX para actuar como reverse-proxy / load balancer de la app |

## Validaciones

| #   | Qué se valida                                                | Comando                                                                                                                    | Resultado esperado                                                                                                       | Evidencia                                                                |
| --- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| 1   | Existe el contexto del cluster                               | `kubectl config get-contexts`                                                                                              | Aparece `docker-desktop`                                                                                                 | [01-contexts.txt](01-contexts.txt)                                       |
| 2   | El nodo está listo                                           | `kubectl get nodes`                                                                                                        | Estado `Ready`                                                                                                           | [02-nodes.txt](02-nodes.txt)                                             |
| 3   | Los pods están listos                                        | `kubectl get pods `                                                                                                        | Log `Escuchando en puerto 3000` por cada réplica                                                                         | [03-pods.txt](03-pods.txt)                                               |
| 4   | El Deployment se despliega por completo                      | `kubectl rollout status deployment/devops-pf-api -n devops-pf`                                                             | `successfully rolled out`                                                                                                | [04-rollout.txt](04-rollout.txt)                                         |
| 5   | Las 2 réplicas arrancaron la app                             | `kubectl logs -n devops-pf -l app=devops-pf-api --prefix`                                                                  | Un log `Escuchando en puerto 3000` por cada Pod (2)                                                                      | [05-logs.txt](05-logs.txt)                                               |
| 6   | El Deployment tiene la configuración declarada               | `kubectl describe deployment devops-pf-api -n devops-pf`                                                                   | 2 réplicas, probes sobre `/health`, requests/limits y `securityContext` no root                                          | [06-describe.txt](06-describe.txt)                                       |
| 7   | El Service existe y es interno                               | `kubectl get svc -n devops-pf`                                                                                             | Tipo `ClusterIP`, puerto `80/TCP`                                                                                        | [07-svc.txt](07-svc.txt)                                                 |
| 8   | El Service apunta a los 2 Pods                               | `kubectl get endpoints -n devops-pf`                                                                                       | 2 IPs con puerto 3000 (no `<none>`)                                                                                      | [08-endpoints.txt](08-endpoints.txt)                                     |
| 9   | La API responde a través del Service                         | `curl.exe -i localhost:8080/health` (con `port-forward` activo)                                                            | `200 OK` con `{"status":"ok"}`                                                                                           | [09-curl_health.txt](09-curl_health.txt)                                 |
| 10  | Las métricas son accesibles a través del Service             | `curl.exe -s localhost:8080/metrics` (con `port-forward` activo)                                                           | Formato Prometheus                                                                                                       | [10-curl_metrics.txt](10-curl_metrics.txt)                               |
| 11  | Un Pod borrado se repone solo                                | `kubectl delete pod <nombre> -n devops-pf` y luego `kubectl get pods -n devops-pf`                                         | Aparece un Pod nuevo y vuelve a haber 2 en `Running`                                                                     | [11-pod_recreado.txt](11-pod_recreado.txt)                               |
| 12  | El Service actualiza sus destinos                            | `kubectl get endpoints -n devops-pf` (después de borrar el Pod)                                                            | 2 IPs, una distinta a la de antes                                                                                        | [12-endpoints_despues.txt](12-endpoints_despues.txt)                     |
| 13  | El Controlador Ingress NGINX está corriendo                  | `kubectl get pods -n ingress-nginx`                                                                                        | Muestra la regla, host y backend configurados                                                                            | [13-ingress_controller.txt](13-ingress_controller.txt)                   |
| 13b | Versión de la imagen del Ingress Controller                  | `kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.template.spec.containers[0].image}'` | registry.k8s.io/ingress-nginx/controller:v1.15.1@sha256:594ceea76b01c592858f803f9ff4d2cb40542cae2060410b2c95f75907d659e1 | [13b-ingress_controller_version.txt](13b-ingress_controller_version.txt) |
| 14  | El recurso Ingress describe reglas de ruteo                  | `kubectl describe ingress devops-pf-api -n devops-pf`                                                                      | Host devops-pf.local mapeado al backend (devops-pf-api:80) y sus Pods destino                                            | [14-ingress.txt](14-ingress.txt)                                         |
| 15  | La API responde a traves de NGINX usando el Host configurado | `curl.exe -i -H "Host: devops-pf.local" http://localhost/health y /metrics`                                                | 200 OK devolviendo el JSON de salud y las métricas de Prometheus                                                         | [15-curl_ingress.txt](15-curl_ingress.txt)                               |
| 16  | NGINX rechaza el tráfico que no tiene el Host correcto       | `curl.exe -i http://localhost/health (sin el header Host)`                                                                 | 404 Not Found emitido por NGINX                                                                                          | [16-curl_sin_host.txt](16-curl_sin_host.txt)                             |

## Conclusión de la prueba de autorreparación

Al borrar el Pod `devops-pf-api-dd7cd6d-6lxdp` (IP `10.1.0.8:3000`), el Deployment creó `devops-pf-api-dd7cd6d-fcdhx` (IP `10.1.0.9:3000`) y el Service actualizó sus endpoints sin intervención manual. Se compara [08-endpoints.txt](08-endpoints.txt) (antes) con [12-endpoints-despues.txt](12-endpoints-despues.txt) (después).

## Cómo reproducirlo

Prerrequisito: imagen local construida (`docker build -t devops-pf-api:1.0.0 ./app`).

    # 1) Base de la aplicación
    kubectl apply -f k8s/namespace.yaml
    kubectl apply -f k8s/deployment.yaml
    kubectl apply -f k8s/service.yaml
    kubectl get pods,svc,endpoints -n devops-pf

    # 2) Ingress Controller (esperar a que esté listo antes del paso 3)
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

    # 3) Reglas de Ingress
    kubectl apply -f k8s/ingress.yaml
    kubectl get ingress -n devops-pf
    kubectl describe ingress devops-pf-api -n devops-pf

    # 4) Pruebas: los dos primeros dan 200 OK, el tercero 404
    curl.exe -i -H "Host: devops-pf.local" http://localhost/health
    curl.exe -i -H "Host: devops-pf.local" http://localhost/metrics
    curl.exe -i http://localhost/health

    # Opcional (solo depuración, bloquea la terminal; usar otra): acceso directo al Service
    kubectl port-forward -n devops-pf svc/devops-pf-api 8080:80

## Instalacion de ingress-nginx v1.15.1

`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml`

Se debe notar que el mantenimiento de este package terminó en marzo de 2026. Se informa en [la web de Ingress-Nginx](https://kubernetes.github.io/ingress-nginx/) que los deployments existentes no se van a romper, pero no habrá bugfixes, updates ni nuevas releases. Solo uso como entorno de prueba.
