#!/usr/bin/env bash
# =============================================================
# scripts/deploy-health-check.sh
# Production-quality deployment health verifier for ssb-app.
# Checks: pod readiness, endpoint liveness, metrics availability,
# HPA status, PDB availability, and recent events.
#
# Usage:
#   bash scripts/deploy-health-check.sh [NAMESPACE] [RELEASE_NAME]
#   bash scripts/deploy-health-check.sh dev ssb-app-dev
#
# Exit codes:
#   0 — All checks passed. Deployment is healthy.
#   1 — One or more checks failed. Deployment needs attention.
#
# Idempotent: Safe to run any number of times. Read-only operations only.
# =============================================================

set -euo pipefail

NAMESPACE="${1:-dev}"
RELEASE="${2:-ssb-app-dev}"
TIMEOUT="${3:-60}"
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*" >&2; FAILED=$((FAILED + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
info() { echo "       $*"; }

echo "=============================================="
echo " SSB App Deployment Health Check"
echo " Namespace:    ${NAMESPACE}"
echo " Release:      ${RELEASE}"
echo " Timestamp:    $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=============================================="
echo ""

# ── Check 1: Deployment exists ─────────────────────────────
echo "Check 1: Deployment exists"
if kubectl get deployment "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
  pass "Deployment '${RELEASE}' found in namespace '${NAMESPACE}'"
else
  fail "Deployment '${RELEASE}' NOT found in namespace '${NAMESPACE}'"
  echo "Skipping remaining checks."
  exit 1
fi

# ── Check 2: All replicas ready ────────────────────────────
echo ""
echo "Check 2: Replica readiness"
DESIRED=$(kubectl get deployment "${RELEASE}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.replicas}')
READY=$(kubectl get deployment "${RELEASE}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
AVAILABLE=$(kubectl get deployment "${RELEASE}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")

info "Desired replicas:   ${DESIRED}"
info "Ready replicas:     ${READY:-0}"
info "Available replicas: ${AVAILABLE:-0}"

if [[ "${READY:-0}" -eq "${DESIRED}" ]]; then
  pass "All ${DESIRED} replicas are ready."
else
  fail "Only ${READY:-0}/${DESIRED} replicas ready."
fi

# ── Check 3: Pod status details ────────────────────────────
echo ""
echo "Check 3: Individual pod status"
POD_LIST=$(kubectl get pods -n "${NAMESPACE}" \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  -o jsonpath='{.items[*].metadata.name}')

if [[ -z "${POD_LIST}" ]]; then
  fail "No pods found for release '${RELEASE}'."
else
  for pod in ${POD_LIST}; do
    POD_PHASE=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.phase}')
    READY_COND=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    RESTARTS=$(kubectl get pod "${pod}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

    if [[ "${POD_PHASE}" == "Running" ]] && [[ "${READY_COND}" == "True" ]]; then
      pass "Pod ${pod}: Running, Ready (restarts: ${RESTARTS})"
      if [[ "${RESTARTS:-0}" -gt 3 ]]; then
        warn "High restart count (${RESTARTS}) — may indicate liveness probe failures."
      fi
    else
      fail "Pod ${pod}: Phase=${POD_PHASE}, Ready=${READY_COND}, Restarts=${RESTARTS}"
    fi
  done
fi

# ── Check 4: Service endpoint health ──────────────────────
echo ""
echo "Check 4: Service endpoint connectivity"
# Port-forward in background, check, then clean up.
FREE_PORT=18080
kubectl port-forward "svc/${RELEASE}" "${FREE_PORT}:80" \
  -n "${NAMESPACE}" &>/dev/null &
PF_PID=$!
sleep 3  # Wait for port-forward to establish.

cleanup_portforward() {
  kill "${PF_PID}" 2>/dev/null || true
}
trap cleanup_portforward EXIT

HEALTH_HTTP=$(curl -sf --max-time 5 -o /tmp/health_resp.json -w "%{http_code}" \
  "http://localhost:${FREE_PORT}/health" 2>/dev/null || echo "000")
if [[ "${HEALTH_HTTP}" == "200" ]]; then
  pass "/health returned HTTP 200"
  info "Response: $(cat /tmp/health_resp.json)"
else
  fail "/health returned HTTP ${HEALTH_HTTP} (expected 200)"
fi

READY_HTTP=$(curl -sf --max-time 5 -w "%{http_code}" -o /dev/null \
  "http://localhost:${FREE_PORT}/ready" 2>/dev/null || echo "000")
if [[ "${READY_HTTP}" == "200" ]]; then
  pass "/ready returned HTTP 200"
else
  fail "/ready returned HTTP ${READY_HTTP} (expected 200)"
fi

METRICS_HTTP=$(curl -sf --max-time 5 -w "%{http_code}" -o /tmp/metrics_resp.txt \
  "http://localhost:${FREE_PORT}/metrics" 2>/dev/null || echo "000")
if [[ "${METRICS_HTTP}" == "200" ]]; then
  METRIC_COUNT=$(grep -c "^ssb_app" /tmp/metrics_resp.txt 2>/dev/null || echo "0")
  pass "/metrics returned HTTP 200 (${METRIC_COUNT} ssb_app_* metrics)"
else
  fail "/metrics returned HTTP ${METRICS_HTTP} (expected 200)"
fi

cleanup_portforward
trap - EXIT

# ── Check 5: HPA status ────────────────────────────────────
echo ""
echo "Check 5: HPA status"
if kubectl get hpa "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
  HPA_CURRENT=$(kubectl get hpa "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.currentReplicas}')
  HPA_DESIRED=$(kubectl get hpa "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.desiredReplicas}')
  HPA_MIN=$(kubectl get hpa "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.minReplicas}')
  HPA_MAX=$(kubectl get hpa "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.maxReplicas}')
  pass "HPA exists: current=${HPA_CURRENT}, desired=${HPA_DESIRED}, min=${HPA_MIN}, max=${HPA_MAX}"
else
  warn "HPA not found — autoscaling disabled (expected in dev)."
fi

# ── Check 6: PDB status ────────────────────────────────────
echo ""
echo "Check 6: PodDisruptionBudget"
if kubectl get pdb "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
  PDB_ALLOWED=$(kubectl get pdb "${RELEASE}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.disruptionsAllowed}')
  pass "PDB exists: disruptions allowed = ${PDB_ALLOWED}"
else
  warn "PDB not found (expected in staging/prod)."
fi

# ── Check 7: Recent warning events ────────────────────────
echo ""
echo "Check 7: Recent warning events (last 10 minutes)"
WARNINGS=$(kubectl get events -n "${NAMESPACE}" \
  --field-selector type=Warning \
  --sort-by='.lastTimestamp' \
  2>/dev/null | grep "${RELEASE}" | tail -5 || true)

if [[ -z "${WARNINGS}" ]]; then
  pass "No recent warning events for release '${RELEASE}'."
else
  warn "Warning events detected:"
  echo "${WARNINGS}"
fi

# ── Check 8: Helm release status ──────────────────────────
echo ""
echo "Check 8: Helm release status"
HELM_STATUS=$(helm status "${RELEASE}" -n "${NAMESPACE}" \
  -o json 2>/dev/null | jq -r '.info.status' || echo "unknown")
if [[ "${HELM_STATUS}" == "deployed" ]]; then
  pass "Helm release status: deployed"
else
  fail "Helm release status: ${HELM_STATUS} (expected 'deployed')"
fi

# ── Summary ────────────────────────────────────────────────
echo ""
echo "=============================================="
if [[ "${FAILED}" -eq 0 ]]; then
  echo -e "${GREEN}RESULT: All checks passed. Deployment is healthy.${NC}"
  echo "=============================================="
  exit 0
else
  echo -e "${RED}RESULT: ${FAILED} check(s) failed. Deployment needs attention.${NC}"
  echo "=============================================="
  exit 1
fi
