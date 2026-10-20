# (golden) Kubestronaut CNCF lab

This is a small one node cluster lab via kind that bootstraps ArgoCD and sets up an app of apps.

The applications are prometheus (PCA), otel (OTCA) and additional argo components like workflows and events (CAPA).

## TODO

Install operators for the o11y stack and manage configs in Argo
Use exemplars to connect metrics/logs/traces
Manage the argo install in Argo
Manage the Argo config in Argo
Install Argo rollouts
Install Argo workflows
Install Argo events
Install gitea
Install harbor
Host a go app in gitea with basic telemetry
Config a webhook event to trigger a workflow build
Config a canary rollout for the app
