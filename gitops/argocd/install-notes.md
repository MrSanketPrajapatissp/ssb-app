# Argo CD Install Notes
#
# Install Argo CD using the official Helm chart.
# Run on the target Kubernetes cluster (kind or EKS).
#
# 1. Add Argo CD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Install Argo CD (version 7.3.4 — pinned)
kubectl create namespace argocd
helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.3.4 \
  --set server.insecure=true \
  --wait \
  --timeout 5m

# 3. Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 4. Access Argo CD UI
kubectl port-forward svc/argocd-server -n argocd 8443:443
# Open: https://localhost:8443 (self-signed cert warning is expected)

# 5. Apply project and application manifests
kubectl apply -f gitops/argocd/ -n argocd

# 6. Install Argo CD CLI (optional, for terminal operations)
VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Rollback via CLI:
# argocd app rollback ssb-app-dev --revision <N>
