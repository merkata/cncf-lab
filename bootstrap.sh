#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cncf-lab"
ARGO_NAMESPACE="argocd"
ISTIO_VERSION="1.32.0"
GATEWAY_API_VERSION="v1.6.3"
# Keep this in sync with expose.clusterIP.staticClusterIP for Harbor in the
# gitops-lab-configs repository (apps/base/harbor.yaml).
HARBOR_CLUSTER_IP="10.96.0.100"

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

if ! eval which istioctl; then
  echo "istioctl CLI not detected, consider installing it (brew install istioctl)"
fi

echo "=== 1. Destroying existing cluster (if present) ==="
kind delete cluster --name "${CLUSTER_NAME}" || true

echo "=== 2. Creating Kind Cluster ==="
kind create cluster --name "${CLUSTER_NAME}" --config kind-config.yaml

# containerd image pulls happen in the node network namespace and use the
# node's resolver, not CoreDNS. Resolve Harbor (and its externalURL host, used
# by Harbor's token service) to the fixed Harbor ClusterIP.
echo "=== 2b. Configuring Harbor name resolution on the kind node ==="
docker exec "${CLUSTER_NAME}-control-plane" sh -c "
  if ! grep -q 'harbor.harbor.svc.cluster.local' /etc/hosts; then
    printf '%s\n' '${HARBOR_CLUSTER_IP} harbor.harbor.svc.cluster.local harbor.127.0.0.1.nip.io' >> /etc/hosts
  fi
"

echo "=== 3. Installing Gateway API CRDs ==="
# The experimental channel includes the TLSRoute and GRPCRoute CRDs this lab
# waits for below. Istio itself works with the standard channel.
kubectl apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
kubectl wait --for=condition=Established --timeout=60s \
  crd/gatewayclasses.gateway.networking.k8s.io \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/grpcroutes.gateway.networking.k8s.io \
  crd/referencegrants.gateway.networking.k8s.io \
  crd/tlsroutes.gateway.networking.k8s.io

echo "=== 4. Installing Istio ==="
# https://istio.io/latest/docs/setup/install/helm/
helm repo add istio https://blob.istio.io/istio-release/charts --force-update
helm repo update
helm install istio-base istio/base \
  -n istio-system \
  --set defaultRevision=default \
  --create-namespace \
  --version "${ISTIO_VERSION}"
helm install istiod istio/istiod \
  -n istio-system \
  --version "${ISTIO_VERSION}" \
  --wait

# The istio/gateway chart deploys the ingress gateway manually. Its Service is
# pinned to the nodePorts mapped in kind-config.yaml, so the host's :80/:443
# reach Envoy. The Gateway resource in gitops-lab-configs links to this Service
# through spec.addresses, so both must live in the same namespace.
kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -
helm install istio-ingress istio/gateway \
  -n istio-ingress \
  --version "${ISTIO_VERSION}" \
  --values istio-gateway-values.yaml \
  --wait

# istiod creates the GatewayClass. Wait for it before Argo CD applies the
# Gateway resource from gitops-lab-configs.
kubectl wait --for=condition=Accepted gatewayclass/istio --timeout=60s

echo "=== 5. Prepare Sealed Secrets ==="
kubectl apply -f gitops/sealed-secrets-key.yaml -n kube-system

echo "=== 6. Installing Argo CD ==="
kubectl create namespace "${ARGO_NAMESPACE}"
helm repo add argo https://argoproj.github.io/argo-helm --force-update
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
echo "  Grafana:    http://grafana.127.0.0.1.nip.io"
echo "  Prometheus: http://prometheus.127.0.0.1.nip.io"
echo "  Argo WF:    http://argo.127.0.0.1.nip.io"
echo "  Gitea:      http://gitea.127.0.0.1.nip.io"
echo "  Harbor:     http://harbor.127.0.0.1.nip.io"
echo "  Jaeger:     http://jaeger.127.0.0.1.nip.io"
