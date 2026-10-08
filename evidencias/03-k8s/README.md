# Paso 3: Kubernetes local

Cluster: Kubernetes integrado en Docker Desktop (contexto `docker-desktop`, 1 nodo).

| #   | Qué se valida                  | Comando                       | Resultado esperado       | Evidencia                          |
| --- | ------------------------------ | ----------------------------- | ------------------------ | ---------------------------------- |
| 1   | Existe el contexto del cluster | `kubectl config get-contexts` | Aparece `docker-desktop` | [01-contexts.txt](01-contexts.txt) |
| 2   | El nodo está listo             | `kubectl get nodes`           | Estado `Ready`           | [02-nodes.txt](02-nodes.txt)       |
