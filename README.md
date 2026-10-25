# (golden) Kubestronaut CNCF lab

This is a small one node cluster lab via kind that bootstraps ArgoCD and sets up an app of apps.

The applications are prometheus (PCA), otel (OTCA) and additional argo components like workflows and events (CAPA).

## DONE

Install Argo rollouts
Install Argo workflows
Install Argo events

## TODO

Install operators for the o11y stack and manage configs in Argo
Use exemplars to connect metrics/logs/traces
Manage the argo install in Argo
Manage the Argo config in Argo
Install gitea
Install harbor
Host a go app in gitea with basic telemetry
  check out go based frameworks in the cncf landscape (go-zero, goFr, kratos)
Config a webhook event to trigger a workflow build
  push to docker
  push to harbor
Config a canary rollout for the app
  deploy from docker (manual)
  deploy from harbor (event)
