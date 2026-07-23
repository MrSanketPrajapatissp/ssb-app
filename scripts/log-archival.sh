#!/usr/bin/env bash
# =============================================================
# scripts/log-archival.sh
# Log archival script for ssb-app on Kubernetes.
# Collects pod logs from all namespaces, compresses them,
# and archives to a local directory (or S3 in production).
#
# Usage:
#   bash scripts/log-archival.sh [NAMESPACES] [OUTPUT_DIR]
#   bash scripts/log-archival.sh "dev staging prod" /tmp/ssb-logs
#
# Features:
#   - Collects logs from all ssb-app pods across specified namespaces
#   - Includes previous container logs (for crash analysis)
#   - Includes Kubernetes events and deployment status
#   - Compresses to timestamped tar.gz archive
#   - Optionally uploads to S3 (if AWS CLI configured)
#   - Idempotent: old archives not overwritten
#
# RPO/RTO Note: This script should run every 6 hours via cron.
# Retention: 30 days local, 90 days S3 (government compliance).
# =============================================================

set -euo pipefail

NAMESPACES="${1:-dev staging prod}"
OUTPUT_DIR="${2:-/home/ec2-user/ssb-logs}"
S3_BUCKET="${SSB_LOG_S3_BUCKET:-}"  # Optional: set env var for S3 upload.
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
ARCHIVE_NAME="ssb-app-logs-${TIMESTAMP}"
WORK_DIR="${OUTPUT_DIR}/${ARCHIVE_NAME}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[LOG-ARCHIVAL]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_warn()  { echo -e "${YELLOW}[LOG-ARCHIVAL]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }
log_error() { echo -e "${RED}[LOG-ARCHIVAL]${NC} $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >&2; }

# ── Setup ─────────────────────────────────────────────────
mkdir -p "${WORK_DIR}"
log_info "Archive directory: ${WORK_DIR}"
log_info "Collecting logs from namespaces: ${NAMESPACES}"

# ── Collect logs per namespace ────────────────────────────
for ns in ${NAMESPACES}; do
  NS_DIR="${WORK_DIR}/${ns}"
  mkdir -p "${NS_DIR}"
  log_info "Processing namespace: ${ns}"

  # Skip if namespace doesn't exist.
  if ! kubectl get namespace "${ns}" &>/dev/null; then
    log_warn "Namespace '${ns}' not found. Skipping."
    continue
  fi

  # Deployment status.
  kubectl get deployment -n "${ns}" -l "app.kubernetes.io/name=ssb-app" \
    -o yaml > "${NS_DIR}/deployment-status.yaml" 2>/dev/null || true

  # Pod list.
  PODS=$(kubectl get pods -n "${ns}" \
    -l "app.kubernetes.io/name=ssb-app" \
    -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "${PODS}" ]]; then
    log_warn "No ssb-app pods found in namespace '${ns}'."
    continue
  fi

  # Collect logs for each pod (current + previous if exists).
  for pod in ${PODS}; do
    POD_DIR="${NS_DIR}/${pod}"
    mkdir -p "${POD_DIR}"
    log_info "  Collecting logs from pod: ${pod}"

    # Current container logs.
    kubectl logs "${pod}" -n "${ns}" \
      --timestamps=true \
      --since=24h \
      2>/dev/null > "${POD_DIR}/current.log" || true

    # Previous container logs (useful for crash analysis).
    kubectl logs "${pod}" -n "${ns}" \
      --previous \
      --timestamps=true \
      2>/dev/null > "${POD_DIR}/previous.log" 2>/dev/null || true

    # Pod describe (events, resource usage).
    kubectl describe pod "${pod}" -n "${ns}" \
      2>/dev/null > "${POD_DIR}/describe.txt" || true
  done

  # Namespace-level events.
  kubectl get events -n "${ns}" \
    --sort-by='.lastTimestamp' \
    2>/dev/null > "${NS_DIR}/events.txt" || true

  # HPA status.
  kubectl get hpa -n "${ns}" -l "app.kubernetes.io/name=ssb-app" \
    -o yaml > "${NS_DIR}/hpa-status.yaml" 2>/dev/null || true

  log_info "Namespace '${ns}' log collection complete."
done

# ── Cluster-level metadata ────────────────────────────────
META_DIR="${WORK_DIR}/cluster-meta"
mkdir -p "${META_DIR}"
kubectl version > "${META_DIR}/kubectl-version.txt" 2>/dev/null || true
kubectl get nodes -o wide > "${META_DIR}/nodes.txt" 2>/dev/null || true
helm list -A > "${META_DIR}/helm-releases.txt" 2>/dev/null || true

# ── Compress archive ──────────────────────────────────────
log_info "Compressing archive..."
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}.tar.gz"
tar -czf "${ARCHIVE_PATH}" -C "${OUTPUT_DIR}" "${ARCHIVE_NAME}"
rm -rf "${WORK_DIR}"

ARCHIVE_SIZE=$(du -sh "${ARCHIVE_PATH}" | cut -f1)
log_info "Archive created: ${ARCHIVE_PATH} (${ARCHIVE_SIZE})"

# ── Optional S3 upload ────────────────────────────────────
if [[ -n "${S3_BUCKET}" ]]; then
  if command -v aws &>/dev/null; then
    log_info "Uploading to s3://${S3_BUCKET}/logs/${ARCHIVE_NAME}.tar.gz..."
    aws s3 cp "${ARCHIVE_PATH}" \
      "s3://${S3_BUCKET}/logs/${ARCHIVE_NAME}.tar.gz" \
      --storage-class STANDARD_IA \
      --metadata "service=ssb-app,timestamp=${TIMESTAMP}"
    log_info "S3 upload complete."
  else
    log_warn "AWS CLI not found. Skipping S3 upload. Archive is local only."
  fi
fi

# ── Cleanup old archives (30-day retention) ───────────────
log_info "Cleaning up archives older than 30 days..."
find "${OUTPUT_DIR}" -name "ssb-app-logs-*.tar.gz" -mtime +30 -delete 2>/dev/null || true

log_info "Log archival complete."
log_info "Archive: ${ARCHIVE_PATH}"
