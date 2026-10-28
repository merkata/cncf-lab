#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cncf-lab"
ARGO_NAMESPACE="argocd"
CILIUM_VERSION="1.19.10"
GATEWAY_API_VERSION="v1.6.3"

if ! eval which kind; then
  echo "You need kind in order to create a k8s cluster, install it first (brew install kind)"
  exit 1
fi

if ! eval which helm; then
  echo "You need helm in order to install argo cd in the k8s cluster, install it first (brew install helm)"
  exit 1
fi

if ! eval which argocd; then
  echo "argocd CLI not detected, consider installing it (brew install argocd)"
fi

if ! eval which argo; then
  echo "argo workflows CLI not detected, consider installing it (brew install argo)"
fi

if ! eval which kubectl; then
  echo "kubectl CLI not detected, consider installing it (brew install kubectl)"
fi

if ! eval which kubectl-argo-rollouts; then
  echo "kubectl argo rollouts CLI not detected, consider installing it (brew install argoproj/tap/kubectl-argo-rollouts)"
fi

if ! eval which kubeseal; then
  echo "kubeseal CLI not detected, consider installing it (brew install kubeseal)"
fi

if ! eval which cilium; then
  echo "cilium CLI not detected, consider installing it (brew install cilium-cli)"
fi

echo "=== 1. Destroying existing cluster (if present) ==="
kind delete cluster --name "${CLUSTER_NAME}" || true

echo "=== 2. Creating Kind Cluster ==="
kind create cluster --name "${CLUSTER_NAME}" --config kind-config.yaml

echo "=== 3. Installing Gateway API CRDs ==="
kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "=== 4. Installing Cilium ==="
API_SERVER_IP=$(kubectl get node "${CLUSTER_NAME}-control-plane" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
helm repo add cilium https://helm.cilium.io
helm repo update
helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --values cilium-values.yaml \
  --set k8sServiceHost="${API_SERVER_IP}" \
  --wait

if command -v cilium >/dev/null 2>&1; then
  cilium status --wait
fi

echo "=== 5. Prepare Sealed Secrets ==="
kubectl apply -f gitops/sealed-secrets-key.yaml -n kube-system

echo "=== 6. Installing Argo CD ==="
kubectl create namespace "${ARGO_NAMESPACE}"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --version 10.11.1 \
  --namespace "${ARGO_NAMESPACE}" \
  --set server.extraArgs="{--insecure}" \
  --set server.service.type=NodePort \
  --set server.service.nodePortHttp=30080 \
  --set configs.cm."resource\.customizations\.health\.argoproj\.io_Application"='
    hs = {}
    hs.status = "Progressing"
    hs.message = ""
    if obj.status ~= nil then
      if obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
    end
    return hs
' \
  --wait

echo "=== 7. Bootstrapping App-of-Apps ==="
kubectl apply -f gitops/root-app.yaml -n "${ARGO_NAMESPACE}"

echo "=== Lab Ready! ==="
echo "Argo CD admin password:"
kubectl -n "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
echo "UIs (after Argo CD syncs the app-of-apps):"
echo "  Argo CD:    http://argocd.127.0.0.1.nip.io"
echo "  Hubble:     http://hubble.127.0.0.1.nip.io"
echo "  Grafana:    http://grafana.127.0.0.1.nip.io"
echo "  Prometheus: http://prometheus.127.0.0.1.nip.io"
echo "  Argo WF:    http://argo.127.0.0.1.nip.io"
echo "  Gitea:      http://gitea.127.0.0.1.nip.io"
echo "  Harbor:     http://harbor.127.0.0.1.nip.io"
echo "  Jaeger:     http://jaeger.127.0.0.1.nip.io"
