#!/bin/bash
# scripts/start-dashboards-bg.sh — Senior DevOps Background Dashboard Daemon

set -e

echo "══════════════════════════════════════════"
echo "  Senior DevOps Dashboard Background Daemon"
echo "══════════════════════════════════════════"

# Stop any stale port-forward processes cleanly
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

# 1. Start Grafana Background Daemon (Port 3000)
nohup kubectl port-forward --address 0.0.0.0 svc/kube-prometheus-stack-grafana -n monitoring 3000:80 > /tmp/grafana-pf.log 2>&1 &
echo "[SUCCESS] Grafana Background Daemon started on Port 3000"

# 2. Start Prometheus Background Daemon (Port 9090)
nohup kubectl port-forward --address 0.0.0.0 svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 > /tmp/prometheus-pf.log 2>&1 &
echo "[SUCCESS] Prometheus Background Daemon started on Port 9090"

# 3. Start App Background Daemon (Port 8080)
nohup kubectl port-forward --address 0.0.0.0 svc/ssb-app-dev -n dev 8080:80 > /tmp/app-pf.log 2>&1 &
echo "[SUCCESS] Go App Background Daemon started on Port 8080"

PUBLIC_IP=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 checkip.amazonaws.com 2>/dev/null || echo "localhost")

echo "══════════════════════════════════════════"
echo "  Live Dashboard URLs:"
echo "  - Grafana:    http://${PUBLIC_IP}:3000"
echo "  - Prometheus: http://${PUBLIC_IP}:9090"
echo "  - Go App:     http://${PUBLIC_IP}:8080/health"
echo "  - Metrics:    http://${PUBLIC_IP}:8080/metrics"
echo "══════════════════════════════════════════"
