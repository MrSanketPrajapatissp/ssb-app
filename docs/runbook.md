# SSB Digital Platform — Alert Runbook & Disaster Recovery

## Alert Runbook

---

### Alert: `SsbAppHighErrorRate`

**Severity:** Critical  
**Trigger:** Error rate > 5% for 2 minutes  
**SLO Impact:** Burns error budget at >10x rate; escalate immediately.

#### Diagnosis Steps

```bash
# 1. Check current error rate
kubectl top pods -n dev -l app.kubernetes.io/name=ssb-app

# 2. Check recent pod logs for errors
kubectl logs -l app.kubernetes.io/name=ssb-app -n dev --tail=100 | grep -E '"level":"error"'

# 3. Check pod restart count (crash-loop indicator)
kubectl get pods -n dev -l app.kubernetes.io/name=ssb-app

# 4. Check Kubernetes events
kubectl get events -n dev --sort-by='.lastTimestamp' | tail -20

# 5. Check if a recent deployment caused the issue
helm history ssb-app-dev -n dev

# 6. PromQL — identify which path is failing
# In Grafana or via port-forward to Prometheus:
# rate(ssb_app_http_requests_total{status_code=~"5..",namespace="dev"}[5m])
```

#### Response Actions

| Condition | Action |
|-----------|--------|
| Recent deployment | `helm rollback ssb-app-dev -n dev` |
| Crash-loop pods | `kubectl describe pod <pod> -n dev` to find OOMKilled or probe failure |
| External dependency | Check if upstream service is down; enable circuit breaker |
| Unknown root cause | Increase log verbosity: `kubectl set env deployment/ssb-app-dev LOG_LEVEL=debug -n dev` |

#### Escalation

- 0–10 min: On-call SRE handles.
- 10–30 min: Escalate to SRE Lead.
- 30+ min: Escalate to Engineering Manager + incident bridge.

---

### Alert: `SsbAppHighP99Latency`

**Severity:** Warning  
**Trigger:** P99 latency > 500ms for 5 minutes  
**SLO Impact:** Latency SLO violation; notify team.

#### Diagnosis Steps

```bash
# 1. Check CPU/memory pressure on pods
kubectl top pods -n dev -l app.kubernetes.io/name=ssb-app

# 2. Check node resource saturation
kubectl top nodes

# 3. Check HPA — are pods scaling?
kubectl get hpa -n dev

# 4. PromQL — identify which percentile is breached
# histogram_quantile(0.99, rate(ssb_app_http_request_duration_seconds_bucket[5m]))
```

#### Response Actions

- If CPU > 80%: Check HPA, manually scale if needed: `kubectl scale deployment ssb-app-dev --replicas=3 -n dev`
- If memory near limit: Check for memory leak patterns in logs
- If all pods are healthy: May be external network latency; check node network metrics

---

### Alert: `SsbAppPodNotReady`

**Severity:** Warning  
**Trigger:** Any ssb-app pod not ready for 3+ minutes

```bash
# Get pod details
kubectl describe pod <pod-name> -n dev

# Check readiness probe failures
kubectl logs <pod-name> -n dev --tail=50

# Force pod restart if stuck
kubectl delete pod <pod-name> -n dev
```

---

### Alert: `SsbAppReplicasMismatch`

**Severity:** Critical  
**Trigger:** Ready replicas < Desired replicas for 5+ minutes

```bash
# Check deployment events
kubectl describe deployment ssb-app-dev -n dev

# Check for pending pods (resource constraints)
kubectl get pods -n dev -l app.kubernetes.io/name=ssb-app
kubectl describe pod <pending-pod> -n dev | grep -A5 Events

# Check if nodes have capacity
kubectl describe nodes | grep -A3 "Allocated resources"
```

---

## Disaster Recovery (DR) Note

### Scope

This DR note covers the ssb-app service and its supporting infrastructure (kind cluster, Prometheus, Argo CD). It does not cover the EC2 instance itself (governed by AWS infrastructure DR).

### Recovery Point Objective (RPO)

| Data Type | RPO |
|-----------|-----|
| Application code (Git) | 0 — always in GitHub |
| Kubernetes manifests | 0 — all in Git (GitOps) |
| Helm values | 0 — all in Git |
| Terraform state | 1 hour (S3 versioning) |
| Application logs | 6 hours (log-archival.sh cadence) |
| Metrics/dashboards | 24 hours (Prometheus default retention) |
| Secrets | N/A — stored in AWS Secrets Manager, not lost |

**Effective RPO: 6 hours** for logs; **0** for all config/code.

### Recovery Time Objective (RTO)

| Scenario | Expected RTO |
|----------|-------------|
| Bad deployment (rollback) | < 2 minutes |
| Pod crash-loop recovery | < 5 minutes (Kubernetes self-heals) |
| Full cluster rebuild (kind) | ~15 minutes (bootstrap.sh) |
| EC2 instance replacement | ~30 minutes (AMI snapshot + bootstrap) |
| Full platform rebuild from scratch | ~60 minutes |

**Target RTO: 60 minutes** for full platform loss.

### Restore Procedure

#### Scenario A: Rollback Bad Deployment

```bash
# 1. Identify the last good Helm revision
helm history ssb-app-dev -n dev

# 2. Roll back to specific revision
helm rollback ssb-app-dev <REVISION> -n dev --wait

# 3. Verify recovery
bash scripts/deploy-health-check.sh dev ssb-app-dev
```

#### Scenario B: Cluster Rebuild

```bash
# 1. Spin up new EC2 instance (or reuse existing)
# 2. Clone repository
git clone https://github.com/ssb-digital/ssb-app.git
cd ssb-app

# 3. Run bootstrap
bash scripts/bootstrap.sh

# 4. Re-deploy via GitOps
kubectl apply -f gitops/argocd/ -n argocd
# Argo CD will auto-sync dev; prod requires manual sync.

# 5. Restore log archives if needed
aws s3 cp s3://${SSB_LOG_S3_BUCKET}/logs/ /home/ec2-user/ssb-logs/ --recursive
```

#### Scenario C: Terraform State Recovery

```bash
# Terraform state is versioned in S3.
# To restore to a previous state:
aws s3api list-object-versions \
  --bucket ssb-digital-terraform-state \
  --prefix dev/terraform.tfstate

# Restore specific version:
aws s3api get-object \
  --bucket ssb-digital-terraform-state \
  --key dev/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.recovered
```

### Restore Verification

After any DR scenario, run:

```bash
# 1. Cluster health
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# 2. Application health
bash scripts/deploy-health-check.sh dev ssb-app-dev

# 3. Monitoring health
kubectl get pods -n monitoring

# 4. Argo CD sync status
argocd app list  # (or check Argo CD UI)
```

### Ownership

| Component | Owner | Escalation |
|-----------|-------|-----------|
| Application | ssb-app team | sre@ssbdigital.com |
| Kubernetes cluster | SRE | sre@ssbdigital.com |
| Terraform / AWS infra | Platform Engineering | platform@ssbdigital.com |
| Monitoring | SRE | sre@ssbdigital.com |
| Secrets | Security | security@ssbdigital.com |
