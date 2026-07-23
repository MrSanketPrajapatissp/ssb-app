# Kyverno Install Notes
#
# Install Kyverno using the official Helm chart.
# Source: https://kyverno.github.io/kyverno/
# Policy patterns: https://github.com/kyverno/policies
#
# 1. Add Kyverno Helm repository
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# 2. Install Kyverno (version 3.2.4 — pinned)
kubectl create namespace kyverno
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --version 3.2.4 \
  --set admissionController.replicas=1 \
  --wait \
  --timeout 5m

# 3. Verify Kyverno is running
kubectl get pods -n kyverno

# 4. Apply ssb-app policies
kubectl apply -f gitops/kyverno/

# 5. Test policies
# Try to create a pod with :latest tag — should be rejected:
kubectl run test-latest --image=nginx:latest -n dev
# Expected: Error from server: [...] "The image tag ':latest' is not allowed."

# 6. Check policy status
kubectl get clusterpolicies
kubectl describe clusterpolicy disallow-latest-tag
