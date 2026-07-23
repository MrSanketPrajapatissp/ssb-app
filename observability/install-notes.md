# kube-prometheus-stack Install Notes
#
# Install kube-prometheus-stack using the official Helm chart.
# This bundles: Prometheus, Grafana, Alertmanager, node-exporter,
# kube-state-metrics in a single, integrated release.
#
# Version: 60.1.0 (pinned)
#
# 1. Add Prometheus community Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Install kube-prometheus-stack
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 60.1.0 \
  --set grafana.adminPassword=admin \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --wait \
  --timeout 10m

# 3. Apply ssb-app observability resources
kubectl apply -f observability/

# 4. Import Grafana dashboard
#    Option A: Via Grafana UI (Dashboards → Import → Upload JSON)
#    Upload: observability/grafana-dashboard.json
#
#    Option B: Via ConfigMap (recommended for GitOps)
kubectl create configmap ssb-app-dashboard \
  --from-file=grafana-dashboard.json=observability/grafana-dashboard.json \
  -n monitoring \
  --dry-run=client -o yaml | \
  kubectl label --local -f - grafana_dashboard=1 -o yaml | \
  kubectl apply -f -

# 5. Access services
# Grafana:      kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Prometheus:   kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
# Alertmanager: kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093

# Default Grafana credentials: admin / admin (change immediately in production)

# 6. Verify ServiceMonitor is picked up
kubectl get servicemonitors -n monitoring
# Prometheus targets: http://localhost:9090/targets
