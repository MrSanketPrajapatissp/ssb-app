# SSB Digital Platform — Architecture

## System Overview

The ssb-app delivery platform is composed of:

1. **Source Control** — GitHub (mono-repo pattern)
2. **CI Pipeline** — GitHub Actions (11-stage pipeline)
3. **Container Registry** — Local Docker registry (kind demo) / AWS ECR (production)
4. **Kubernetes** — Local kind cluster (demo) / AWS EKS (production design)
5. **GitOps Controller** — Argo CD
6. **Secret Management** — Kubernetes Secrets + AWS Secrets Manager (production)
7. **Monitoring** — kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
8. **Policy** — Kyverno
9. **Cloud Infrastructure** — Terraform (EKS + VPC + IAM) — validate/plan only

---

## Architecture Diagram (ASCII)

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          SOURCE CONTROL (GitHub)                            │
│                        github.com/ssb-digital/ssb-app                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ app/     │  │ helm/    │  │ infra/   │  │ gitops/  │  │ observabil/ │  │
│  │ (Go src) │  │(Helm chrt│  │(Terraform│  │(ArgoCD/  │  │(Prometheus  │  │
│  │Dockerfile│  │ dev/stg/ │  │  EKS/VPC │  │ Kyverno) │  │  Rules/Dash)│  │
│  │          │  │ prod vals│  │  IAM)    │  │          │  │             │  │
│  └────┬─────┘  └──────────┘  └──────────┘  └──────────┘  └─────────────┘  │
└───────┼────────────────────────────────────────────────────────────────────┘
        │ git push to main
        ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                     CI/CD PIPELINE (GitHub Actions)                        │
│                                                                             │
│  Lint/Test → Build → Trivy Scan → SBOM → Tag → Push → Helm Lint           │
│      └──────────────────────────────────────────────────────────►          │
│                                                         Deploy Dev (auto)   │
│                                                              │              │
│                                                     Smoke Test              │
│                                                              │              │
│                                              Manual Approval Gate           │
│                                                              │              │
│                                                    Deploy Prod              │
│                                               (with auto-rollback)          │
└───────────────────────────────────────────────────────────────────────────┘
        │                               │
        │ push image                    │ update Helm values
        ▼                               ▼
┌─────────────────┐          ┌──────────────────────────────────────────────┐
│ CONTAINER       │          │         LOCAL kind CLUSTER                    │
│ REGISTRY        │          │ (or AWS EKS in production design)             │
│                 │          │                                               │
│ localhost:5001  │◄─────────┤  ┌──────────────────────────────────────┐    │
│ (kind demo)     │  pull    │  │              ARGO CD (argocd ns)      │    │
│                 │          │  │  app-dev: auto-sync (main branch)     │    │
│ ECR (prod)      │          │  │  app-stg: manual sync                │    │
│ KMS encrypted   │          │  │  app-prod: manual sync (v* tag)      │    │
│ Immutable tags  │          │  └───────────┬──────────────────────────┘    │
│ Scan on push    │          │              │ deploys via Helm                │
└─────────────────┘          │              ▼                               │
                             │  ┌──────────────────────────────────────┐    │
                             │  │         NAMESPACES                   │    │
                             │  │                                       │    │
                             │  │  ┌──────────┐  ┌──────────┐         │    │
                             │  │  │   dev    │  │ staging  │         │    │
                             │  │  │ (1 pod)  │  │ (2 pods) │         │    │
                             │  │  │ auto-HPA │  │ HPA+PDB  │         │    │
                             │  │  └──────────┘  └──────────┘         │    │
                             │  │  ┌──────────┐                        │    │
                             │  │  │   prod   │                        │    │
                             │  │  │ (3 pods) │                        │    │
                             │  │  │ HPA+PDB  │                        │    │
                             │  │  │ 3-zone   │                        │    │
                             │  │  └──────────┘                        │    │
                             │  └──────────────────────────────────────┘    │
                             │                                               │
                             │  ┌──────────────────────────────────────┐    │
                             │  │     SECURITY LAYER                    │    │
                             │  │  Kyverno: disallow-latest-tag         │    │
                             │  │           require-non-root            │    │
                             │  │           require-pod-probes          │    │
                             │  │  RBAC: least-privilege service accts  │    │
                             │  │  NetworkPolicy: default-deny ingress  │    │
                             │  └──────────────────────────────────────┘    │
                             │                                               │
                             │  ┌──────────────────────────────────────┐    │
                             │  │     OBSERVABILITY (monitoring ns)     │    │
                             │  │  Prometheus → scrapes /metrics         │    │
                             │  │  Grafana → SSB App dashboard          │    │
                             │  │  Alertmanager → Slack/PagerDuty       │    │
                             │  │  PrometheusRule: 4 alerts, 2 SLOs     │    │
                             │  └──────────────────────────────────────┘    │
                             └───────────────────────────────────────────────┘
                                                │
                                                │ (design-only boundary)
                                                ▼
                             ┌───────────────────────────────────────────────┐
                             │        TERRAFORM-MANAGED CLOUD (AWS)           │
                             │              [DESIGN ONLY — no apply]          │
                             │                                               │
                             │  VPC (3 AZs, public+private subnets)         │
                             │  EKS Cluster (1.29, private endpoint)        │
                             │  Node Groups: system (m5.large) + app        │
                             │  ECR Repository (immutable, KMS, scan)       │
                             │  IAM: IRSA roles + GitHub OIDC CI role       │
                             │  KMS: secrets + state encryption              │
                             │  CloudWatch: VPC flow logs (90-day)          │
                             │  S3: Terraform state (versioned, encrypted)   │
                             │  DynamoDB: Terraform state locking            │
                             └───────────────────────────────────────────────┘
```

---

## Progressive Delivery: Rolling Update Strategy

```
BEFORE:     [Pod v1.0] [Pod v1.0] [Pod v1.0]   ← 3 pods serving traffic

DEPLOY v1.1:
Step 1:     [Pod v1.0] [Pod v1.0] [Pod v1.0] [Pod v1.1]  ← surge +1
             (maxSurge=1, maxUnavailable=0)
Step 2:     WAIT: v1.1 pod passes readiness probe
Step 3:     [Pod v1.0] [Pod v1.0] [Pod v1.1]             ← remove 1 old
Step 4:     [Pod v1.0] [Pod v1.0] [Pod v1.1] [Pod v1.1]  ← surge again
Step 5:     [Pod v1.0] [Pod v1.1] [Pod v1.1]             ← remove 1 old
...

AFTER:      [Pod v1.1] [Pod v1.1] [Pod v1.1]   ← all updated, zero downtime

ROLLBACK:   helm rollback ssb-app-dev → immediate
            Argo CD rollback: argocd app rollback ssb-app-dev
```

**Promotion Criteria:** All pods pass readiness probe + smoke test returns HTTP 200 on /health, /ready, /metrics.  
**Rollback Criteria:** Any pod fails liveness probe 3 times OR smoke test fails after deploy.

---

## Security Boundary: Secrets Flow

```
[Developer] → GitHub Secrets → GitHub Actions OIDC → AWS IAM Role
                                                            │
                                                    (no long-lived keys)
                                                            │
                                            ┌───────────────▼──────────┐
                                            │   AWS Secrets Manager    │
                                            │   (KMS encrypted)        │
                                            └───────────────┬──────────┘
                                                            │ ESO (External Secrets Operator)
                                                            ▼
                                            ┌───────────────────────────┐
                                            │  Kubernetes Secret        │
                                            │  (in-cluster, RBAC gated) │
                                            └───────────────────────────┘
                                                            │
                                                   mounted as env var
                                                            ▼
                                            ┌───────────────────────────┐
                                            │  ssb-app Pod              │
                                            │  (reads from env only)    │
                                            └───────────────────────────┘
```
