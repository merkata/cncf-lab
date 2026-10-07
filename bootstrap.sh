#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cncf-lab"
ARGO_NAMESPACE="argocd"

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

if ! eval which kubectl; then
  echo "kubectl CLI not detected, consider installing it (brew install kubectl)"
fi

echo "=== 1. Destroying existing cluster (if present) ==="
kind delete cluster --name "${CLUSTER_NAME}" || true

echo "=== 2. Creating Kind Cluster ==="
kind create cluster --name "${CLUSTER_NAME}" --config kind-config.yaml

echo "=== 3. Installing Argo CD ==="
kubectl create namespace "${ARGO_NAMESPACE}"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm upgrade --install argocd argo/argo-cd \
  --namespace "${ARGO_NAMESPACE}" \
  --set server.extraArgs="{--insecure}" \
  --wait

echo "=== 4. Bootstrapping App-of-Apps ==="
kubectl apply -f gitops/root-app.yaml -n "${ARGO_NAMESPACE}"

echo "=== Lab Ready! ==="
echo "Argo CD admin password:"
kubectl -n "${ARGO_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
echo "Port-forward Argo CD UI:"
echo "kubectl port-forward svc/argocd-server -n ${ARGO_NAMESPACE} 8080:443"
