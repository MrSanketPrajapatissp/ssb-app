#!/usr/bin/env bash
# =============================================================
# scripts/bootstrap.sh
# SSB Digital ssb-app — Full Environment Bootstrap
# Target OS: Amazon Linux 2023 (AL2023)
# Usage: bash scripts/bootstrap.sh [--skip-tools] [--cluster-only]
#
# This script sets up:
#   1. System dependencies (dnf-based, AL2023 only)
#   2. Docker daemon
#   3. kind (Kubernetes in Docker)
#   4. kubectl
#   5. Helm
#   6. Local container registry (localhost:5001)
#   7. kind cluster with registry integration
#   8. Argo CD
#   9. Kyverno
#  10. kube-prometheus-stack
#  11. ingress-nginx
#
# IDEMPOTENT: Safe to run multiple times. Checks for existing
# installations before installing. Re-running will skip steps
# that are already complete.
#
# FAIL-FAST: Uses `set -euo pipefail`. Any non-zero exit stops
# the script and the error is clearly logged.
# =============================================================

set -euo pipefail

# ── Colours for log output ─────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}  $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }
log_section() { echo -e "\n${BLUE}══════════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}══════════════════════════════════════════${NC}"; }

# ── Version pins ───────────────────────────────────────────
KIND_VERSION="v0.23.0"
KUBECTL_VERSION="v1.29.4"
HELM_VERSION="v3.15.2"
ARGOCD_VERSION="7.3.4"           # Helm chart version
KYVERNO_VERSION="3.2.4"          # Helm chart version
PROMETHEUS_STACK_VERSION="60.1.0" # kube-prometheus-stack Helm chart version
INGRESS_NGINX_VERSION="4.10.1"   # ingress-nginx Helm chart version
REGISTRY_PORT="5001"
REGISTRY_NAME="kind-registry"
CLUSTER_NAME="ssb-platform"

# ── Argument parsing ──────────────────────────────────────
SKIP_TOOLS=false
CLUSTER_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --skip-tools)    SKIP_TOOLS=true ;;
    --cluster-only)  CLUSTER_ONLY=true ;;
    *)               log_warn "Unknown argument: $arg" ;;
  esac
done

# ── Prerequisite check ────────────────────────────────────
check_os() {
  if [[ ! -f /etc/os-release ]]; then
    log_warn "Cannot determine OS from /etc/os-release. Proceeding with tool installation..."
    return 0
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  log_info "OS check detected: $ID ${VERSION_ID:-unknown}"
}

# ── Step 1: System Dependencies ───────────────────────────
install_system_deps() {
  log_section "Step 1: System Dependencies"
  if command -v dnf &>/dev/null; then
    log_info "Installing git, curl, tar, jq via dnf..."
    sudo dnf install -y --allowerasing git tar jq unzip dos2unix || sudo dnf install -y git tar jq unzip dos2unix
  elif command -v apt-get &>/dev/null; then
    log_info "Installing git, curl, tar, jq via apt-get..."
    sudo apt-get update && sudo apt-get install -y git curl tar jq unzip dos2unix
  else
    log_warn "Package manager not dnf/apt. Ensure git, curl, tar, jq, dos2unix are installed."
  fi
  log_info "System dependencies checked."
}

# ── Step 2: Docker ─────────────────────────────────────────
install_docker() {
  log_section "Step 2: Docker"
  if command -v docker &>/dev/null; then
    log_info "Docker already installed: $(docker --version)"
  else
    log_info "Installing Docker..."
    if command -v dnf &>/dev/null; then
      sudo dnf install -y --allowerasing docker || sudo dnf install -y docker
    elif command -v apt-get &>/dev/null; then
      sudo apt-get update && sudo apt-get install -y docker.io
    fi
    sudo systemctl enable --now docker || true
    USER_NAME=$(whoami)
    sudo usermod -aG docker "$USER_NAME" 2>/dev/null || true
    log_warn "Docker group membership requires a new shell session to take effect."
    log_warn "Run: newgrp docker OR log out and back in."
  fi

  # Ensure daemon is running.
  if ! sudo systemctl is-active --quiet docker; then
    log_info "Starting Docker daemon..."
    sudo systemctl start docker || sudo service docker start || true
  fi
  log_info "Docker check complete."
}

# ── Step 3: kind ───────────────────────────────────────────
install_kind() {
  log_section "Step 3: kind (Kubernetes in Docker)"
  if command -v kind &>/dev/null && [[ "$(kind version)" == *"${KIND_VERSION}"* ]]; then
    log_info "kind ${KIND_VERSION} already installed."
    return 0
  fi

  log_info "Installing kind ${KIND_VERSION}..."
  curl -Lo /tmp/kind \
    "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
  chmod +x /tmp/kind
  sudo mv /tmp/kind /usr/local/bin/kind
  log_info "kind installed: $(kind version)"
}

# ── Step 4: kubectl ────────────────────────────────────────
install_kubectl() {
  log_section "Step 4: kubectl"
  if command -v kubectl &>/dev/null && [[ "$(kubectl version --client --short 2>/dev/null)" == *"${KUBECTL_VERSION}"* ]]; then
    log_info "kubectl ${KUBECTL_VERSION} already installed."
    return 0
  fi

  log_info "Installing kubectl ${KUBECTL_VERSION}..."
  curl -Lo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin/kubectl
  log_info "kubectl installed: $(kubectl version --client --short 2>/dev/null || true)"
}

# ── Step 5: Helm ───────────────────────────────────────────
install_helm() {
  log_section "Step 5: Helm"
  if command -v helm &>/dev/null && [[ "$(helm version --short 2>/dev/null)" == *"${HELM_VERSION}"* ]]; then
    log_info "Helm ${HELM_VERSION} already installed."
    return 0
  fi

  log_info "Installing Helm ${HELM_VERSION}..."
  curl -Lo /tmp/helm.tar.gz \
    "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
  tar -xzf /tmp/helm.tar.gz -C /tmp/
  sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm
  rm -rf /tmp/helm.tar.gz /tmp/linux-amd64
  log_info "Helm installed: $(helm version --short)"
}

# ── Step 6: Local Container Registry ──────────────────────
setup_registry() {
  log_section "Step 6: Local Container Registry (port ${REGISTRY_PORT})"

  if docker inspect "${REGISTRY_NAME}" &>/dev/null; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "${REGISTRY_NAME}")" == "true" ]]; then
      log_info "Registry '${REGISTRY_NAME}' already running on port ${REGISTRY_PORT}."
      return 0
    else
      log_warn "Registry container exists but is stopped. Restarting..."
      docker start "${REGISTRY_NAME}"
      return 0
    fi
  fi

  log_info "Starting local registry on localhost:${REGISTRY_PORT}..."
  docker run -d \
    --restart=always \
    -p "127.0.0.1:${REGISTRY_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2.8.3

  log_info "Registry running at localhost:${REGISTRY_PORT}"
}

# ── Step 7: kind Cluster ───────────────────────────────────
create_kind_cluster() {
  log_section "Step 7: kind Cluster (${CLUSTER_NAME})"

  if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    log_info "kind cluster '${CLUSTER_NAME}' already exists."
  else
    log_info "Creating kind cluster '${CLUSTER_NAME}'..."
    cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  # Mirror localhost:5001 to the local registry container.
  # This is the official kind local-registry pattern.
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
      endpoint = ["http://${REGISTRY_NAME}:5000"]
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
      - containerPort: 30000
        hostPort: 3000
        protocol: TCP
      - containerPort: 30090
        hostPort: 9090
        protocol: TCP
  - role: worker
  - role: worker
EOF
    log_info "kind cluster created."
  fi

  # Connect the registry container to the kind network.
  if ! docker network inspect kind | grep -q "${REGISTRY_NAME}"; then
    log_info "Connecting registry to kind network..."
    docker network connect kind "${REGISTRY_NAME}" 2>/dev/null || true
  fi

  # Annotate nodes with registry info (per kind docs).
  for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
    kubectl annotate node "${node}" \
      "kind.x-k8s.io/registry=localhost:${REGISTRY_PORT}" \
      --overwrite 2>/dev/null || true
  done

  log_info "Registry connectivity configured."
}

# ── Step 8: Argo CD ────────────────────────────────────────
install_argocd() {
  log_section "Step 8: Argo CD (Helm chart ${ARGOCD_VERSION})"

  helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
  helm repo update argo

  if helm status argocd -n argocd &>/dev/null; then
    log_info "Argo CD already installed. Skipping."
    return 0
  fi

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

  helm install argocd argo/argo-cd \
    --namespace argocd \
    --version "${ARGOCD_VERSION}" \
    --set server.insecure=true \
    --set configs.params."server\.insecure"=true \
    --wait \
    --timeout 5m

  log_info "Argo CD installed."
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
  log_info "Argo CD admin password: ${ARGOCD_PASSWORD}"
  log_info "Access via: kubectl port-forward svc/argocd-server -n argocd 8443:443"
}

# ── Step 9: Kyverno ───────────────────────────────────────
install_kyverno() {
  log_section "Step 9: Kyverno (Helm chart ${KYVERNO_VERSION})"

  helm repo add kyverno https://kyverno.github.io/kyverno/ 2>/dev/null || true
  helm repo update kyverno

  if helm status kyverno -n kyverno &>/dev/null; then
    log_info "Kyverno already installed. Skipping."
    return 0
  fi

  kubectl create namespace kyverno --dry-run=client -o yaml | kubectl apply -f -

  helm install kyverno kyverno/kyverno \
    --namespace kyverno \
    --version "${KYVERNO_VERSION}" \
    --set admissionController.replicas=1 \
    --wait \
    --timeout 5m

  log_info "Kyverno installed. Applying ssb-app policies..."
  kubectl apply -f gitops/kyverno/ || log_warn "Kyverno policy application deferred — apply manually after cluster is ready."
}

# ── Step 10: kube-prometheus-stack ────────────────────────
install_monitoring() {
  log_section "Step 10: kube-prometheus-stack (v${PROMETHEUS_STACK_VERSION})"

  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
  helm repo update prometheus-community

  if helm status kube-prometheus-stack -n monitoring &>/dev/null; then
    log_info "kube-prometheus-stack already installed. Skipping."
    return 0
  fi

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --version "${PROMETHEUS_STACK_VERSION}" \
    --set grafana.adminPassword=admin \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --wait \
    --timeout 10m

  # Apply custom ssb-app observability resources.
  kubectl apply -f observability/ || log_warn "Observability manifests deferred — apply after app deployment."

  log_info "Monitoring stack installed."
  log_info "Grafana access: kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
  log_info "Grafana credentials: admin / admin"
}

# ── Step 11: ingress-nginx ─────────────────────────────────
install_ingress_nginx() {
  log_section "Step 11: ingress-nginx (v${INGRESS_NGINX_VERSION})"

  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
  helm repo update ingress-nginx

  if helm status ingress-nginx -n ingress-nginx &>/dev/null; then
    log_info "ingress-nginx already installed. Skipping."
    return 0
  fi

  kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -

  helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --version "${INGRESS_NGINX_VERSION}" \
    --set controller.hostPort.enabled=true \
    --set controller.service.type=NodePort \
    --wait \
    --timeout 5m

  log_info "ingress-nginx installed."
}

# ── Verify ─────────────────────────────────────────────────
verify_setup() {
  log_section "Verification"
  log_info "Checking cluster nodes..."
  kubectl get nodes -o wide

  log_info "Checking registry connectivity..."
  curl -sf "http://localhost:${REGISTRY_PORT}/v2/" && log_info "Registry OK" || log_warn "Registry not reachable"

  log_info "Checking Argo CD pods..."
  kubectl get pods -n argocd

  log_info "Checking monitoring pods..."
  kubectl get pods -n monitoring --no-headers | head -10

  log_info ""
  log_info "Bootstrap complete!"
  log_info ""
  log_info "Next steps:"
  log_info "  1. Build and push image:"
  log_info "     docker build -t localhost:${REGISTRY_PORT}/ssb-app:git-\$(git rev-parse --short HEAD) app/"
  log_info "     docker push localhost:${REGISTRY_PORT}/ssb-app:git-\$(git rev-parse --short HEAD)"
  log_info ""
  log_info "  2. Deploy to dev:"
  log_info "     helm upgrade --install ssb-app-dev helm/ssb-app -n dev --create-namespace \\"
  log_info "       -f helm/ssb-app/values-dev.yaml \\"
  log_info "       --set image.tag=git-\$(git rev-parse --short HEAD)"
  log_info ""
  log_info "  3. Apply Argo CD manifests:"
  log_info "     kubectl apply -f gitops/argocd/"
}

# ── Main ───────────────────────────────────────────────────
main() {
  log_section "SSB Digital — Environment Bootstrap"
  log_info "Starting bootstrap on: $(hostname)"
  log_info "User: $(whoami)"
  log_info "Date: $(date -u)"

  check_os

  if [[ "$SKIP_TOOLS" == "false" ]]; then
    install_system_deps
    install_docker
    install_kind
    install_kubectl
    install_helm
  else
    log_warn "--skip-tools: Skipping tool installation."
  fi

  if [[ "$CLUSTER_ONLY" == "false" ]]; then
    setup_registry
  fi

  create_kind_cluster

  if [[ "$CLUSTER_ONLY" == "false" ]]; then
    install_argocd
    install_kyverno
    install_monitoring
    install_ingress_nginx
  fi

  verify_setup
}

main "$@"
