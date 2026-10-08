# Paso 3: Kubernetes local

Cluster: Kubernetes integrado en Docker Desktop (contexto `docker-desktop`, 1 nodo).

| #   | Qué se valida                                  | Comando                                                        | Resultado esperado                                                              | Evidencia                          |
| --- | ---------------------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------- |
| 1   | Existe el contexto del cluster                 | `kubectl config get-contexts`                                  | Aparece `docker-desktop`                                                        | [01-contexts.txt](01-contexts.txt) |
| 2   | El nodo está listo                             | `kubectl get nodes`                                            | Estado `Ready`                                                                  | [02-nodes.txt](02-nodes.txt)       |
| 3   | Los pods están listos                          | `kubectl get pods `                                            | Log `Escuchando en puerto 3000` por cada réplica                                | [03-pods.txt](02-pods.txt)         |
| 4   | El Deployment se despliega por completo        | `kubectl rollout status deployment/devops-pf-api -n devops-pf` | `successfully rolled out`                                                       | [04-rollout.txt](04-rollout.txt)   |
| 5   | Las 2 réplicas arrancaron la app               | `kubectl logs -n devops-pf -l app=devops-pf-api --prefix`      | Un log `Escuchando en puerto 3000` por cada Pod (2)                             | [05-logs.txt](05-logs.txt)         |
| 6   | El Deployment tiene la configuración declarada | `kubectl describe deployment devops-pf-api -n devops-pf`       | 2 réplicas, probes sobre `/health`, requests/limits y `securityContext` no root | [06-describe.txt](06-describe.txt) |
