# SSB Digital — ssb-app DevOps Platform

> **Government-grade delivery platform for the ssb-app HTTP service.**  
> Secure · Reproducible · Auditable · Observable  
> Assignment Version: 20 Jul 2026

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Environment Variables](#2-environment-variables)
3. [Local Setup (Kind + EC2)](#3-local-setup)
4. [Exact Run Commands](#4-exact-run-commands)
5. [Pipeline Flow](#5-pipeline-flow)
6. [Architecture Decisions](#6-architecture-decisions)
7. [Assumptions](#7-assumptions)
8. [Cleanup](#8-cleanup)

---

## 1. Prerequisites

> **Target OS: Amazon Linux 2023 (AL2023) on AWS EC2**  
> Everything below must run on the EC2 instance, not your local Windows machine.

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Docker | 24.x | `sudo dnf install -y docker` |
| kind | v0.23.0 | Auto-installed by bootstrap.sh |
| kubectl | v1.29.4 | Auto-installed by bootstrap.sh |
| Helm | v3.15.2 | Auto-installed by bootstrap.sh |
| Git | 2.x | `sudo dnf install -y git` |
| curl | Any | `sudo dnf install -y curl` |
| dos2unix | Any | `sudo dnf install -y dos2unix` |

**Minimum EC2 spec:** `t3.large` (2 vCPU, 8 GB RAM) or larger.  
`t3.xlarge` recommended for running all monitoring components.

---

## 2. Environment Variables

Copy `.env.example` and populate before running scripts:

```bash
cp .env.example .env
# Edit .env — DO NOT commit .env to git
```

| Variable | Purpose | Example |
|----------|---------|---------|
| `REGISTRY` | Container registry URL | `localhost:5001` |
| `AWS_ACCOUNT_ID` | AWS account for Terraform | `123456789012` |
| `AWS_REGION` | AWS region for Terraform | `ap-south-1` |
| `SSB_LOG_S3_BUCKET` | S3 bucket for log archival | `ssb-logs-bucket` |
| `KUBECONFIG_DEV` | Base64 kubeconfig for dev (CI) | *Set as GitHub secret* |
| `KUBECONFIG_PROD` | Base64 kubeconfig for prod (CI) | *Set as GitHub secret* |

---

## 3. Local Setup

### Step 1: Transfer files to EC2

```bash
# From your Windows machine (PowerShell):
scp -r ssb-app/ ec2-user@<EC2_IP>:/home/ec2-user/ssb-app

# On EC2: Fix line endings
sudo dnf install -y dos2unix
find /home/ec2-user/ssb-app -type f \( -name "*.sh" -o -name "*.yaml" -o -name "*.yml" \
  -o -name "*.tf" -o -name "*.go" -o -name "Dockerfile" \) -exec dos2unix {} \;

chmod +x /home/ec2-user/ssb-app/scripts/*.sh
cd /home/ec2-user/ssb-app
```

### Step 2: Run Bootstrap

```bash
# Full bootstrap (installs all tools, creates cluster, installs Argo CD, monitoring, etc.)
bash scripts/bootstrap.sh

# After bootstrap, start a new shell session for Docker group membership:
newgrp docker
```

### Step 3: Build and Push Image

```bash
SHORT_SHA=$(git rev-parse --short HEAD)
docker build \
  --build-arg VERSION="1.0.0" \
  --build-arg GIT_COMMIT="$SHORT_SHA" \
  --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t localhost:5001/ssb-app:git-${SHORT_SHA} \
  app/

docker push localhost:5001/ssb-app:git-${SHORT_SHA}
```

### Step 4: Run Go Tests

```bash
cd app
go test -race -v ./...
cd ..
```

### Step 5: Deploy to dev

```bash
helm upgrade --install ssb-app-dev helm/ssb-app \
  --namespace dev \
  --create-namespace \
  -f helm/ssb-app/values-dev.yaml \
  --set image.tag="git-$(git rev-parse --short HEAD)" \
  --atomic \
  --timeout 120s \
  --wait
```

### Step 6: Verify Deployment

```bash
# Run health check
bash scripts/deploy-health-check.sh dev ssb-app-dev

# Port-forward and test manually
kubectl port-forward svc/ssb-app-dev 8080:80 -n dev &
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/metrics | head -20
```

### Step 7: Run Helm Tests

```bash
helm test ssb-app-dev -n dev
```

### Step 8: Apply Argo CD and Kyverno

```bash
# Apply Argo CD project and applications
kubectl apply -f gitops/argocd/ -n argocd

# Apply Kyverno policies
kubectl apply -f gitops/kyverno/

# Apply observability resources
kubectl apply -f observability/
```

### Step 9: Terraform Validate/Plan (Design-only)

```bash
cd infra/environments/dev
terraform init -backend=false
terraform validate
terraform plan -var-file=terraform.tfvars | head -50

cd ../staging
terraform init -backend=false
terraform validate

cd ../prod
terraform init -backend=false
terraform validate
```

### Step 10: Failure Simulation

```bash
bash scripts/failure-simulation.sh dev ssb-app-dev
```

---

## 4. Exact Run Commands

| Goal | Command |
|------|---------|
| Full bootstrap | `bash scripts/bootstrap.sh` |
| Go tests | `cd app && go test -race ./...` |
| Helm lint (all envs) | `helm lint helm/ssb-app --strict` |
| Terraform validate | `cd infra/environments/dev && terraform init -backend=false && terraform validate` |
| Deploy dev | `helm upgrade --install ssb-app-dev helm/ssb-app -n dev -f helm/ssb-app/values-dev.yaml --set image.tag=git-$(git rev-parse --short HEAD) --atomic` |
| Deploy staging | `helm upgrade --install ssb-app-staging helm/ssb-app -n staging -f helm/ssb-app/values-staging.yaml --set image.tag=git-$(git rev-parse --short HEAD) --atomic` |
| Helm tests | `helm test ssb-app-dev -n dev` |
| Health check | `bash scripts/deploy-health-check.sh dev ssb-app-dev` |
| Failure simulation | `bash scripts/failure-simulation.sh dev ssb-app-dev` |
| Log archival | `bash scripts/log-archival.sh "dev staging" /tmp/ssb-logs` |
| Rollback | `helm rollback ssb-app-dev -n dev` |
| Grafana access | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80` |
| Argo CD access | `kubectl port-forward svc/argocd-server -n argocd 8443:443` |

---

## 5. Pipeline Flow

```
[git push to main]
       │
       ▼
[1. Lint & Test]
  ├─ go vet ./...
  ├─ staticcheck
  └─ go test -race ./...
       │
       ▼
[2. Build Image]
  └─ docker buildx build (multi-stage, non-root)
       │
       ▼
[3. Trivy Vulnerability Scan]
  └─ Fails on HIGH/CRITICAL fixable CVEs
       │
       ▼
[4. SBOM Generation]
  └─ Anchore Syft → SPDX JSON artifact
       │
       ▼
[5. Immutable Tag]
  └─ git-<sha> + semver (on v* tags)
       │
       ▼
[6. Registry Push]
  └─ localhost:5001 (kind) / ECR (prod)
       │
       ▼
[7. Helm Lint + Kubeval]
  └─ All 3 environment value files
       │
       ▼
[8. Deploy to dev]
  └─ helm upgrade --atomic (auto-rollback on failure)
       │
       ▼
[10. Smoke Test (dev)]
  └─ helm test + curl /health /ready /metrics
       │
       ▼
[9. Manual Approval Gate] ← Human reviews in GitHub UI
       │
       ▼
[Deploy to prod]
  └─ helm upgrade --atomic + post-deploy smoke test
       │  (on failure)
       └─ [11. Automated Rollback]
             └─ helm rollback <prev-revision>
```

---

## 6. Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Service language** | Go 1.22 | Zero-dependency binary, tiny image, native Prometheus client |
| **Base runtime image** | `distroless/static-debian12:nonroot` | No shell attack surface, minimal CVEs, non-root |
| **CI/CD** | GitHub Actions | Widest action ecosystem, native OIDC for AWS auth |
| **Kubernetes cluster** | kind (Kubernetes in Docker) | Official recommendation, free, runs on single EC2 |
| **Container registry** | Local Docker registry on port 5001 | Official kind pattern, no DockerHub dependency |
| **Progressive delivery** | Rolling updates (Helm + Argo CD) | Zero extra infra cost; maxUnavailable=0 ensures no downtime; instant rollback via `helm rollback` |
| **GitOps** | Argo CD | Industry standard; dev auto-sync, prod manual-sync for safety |
| **Policy-as-code** | Kyverno | CRD-based policies, simpler than OPA/Gatekeeper, strong community |
| **Cloud Terraform** | AWS EKS | Government-preferred; terraform-aws-modules support; matches context |
| **State backend** | S3 + DynamoDB | Encrypted, versioned, locked; no Terraform Cloud dependency |
| **Observability** | kube-prometheus-stack | Community standard bundle; minimal config duplication |
| **Secret management** | Placeholder + ESO (design) | No real secrets in demo; ESO + Secrets Manager for production |
| **Bonus** | Supply-chain hardening | Cosign image signing, SBOM generation, provenance attestation |

---

## 7. Assumptions

1. The EC2 instance has outbound internet access for `dnf install`, `kind` binary download, and Helm chart pulls.
2. The kind cluster runs entirely locally on the EC2 instance — no external load balancer is provisioned.
3. Terraform is run in validate/plan mode only. No real AWS credentials are required. Mock values are used.
4. The GitHub Actions pipeline requires three repository secrets: `KUBECONFIG_DEV`, `KUBECONFIG_PROD`, `REGISTRY`.
5. The Grafana dashboard is imported manually via the UI or provisioned via a ConfigMap (pattern documented in `observability/install-notes.md`).
6. TLS is assumed at the Ingress level via cert-manager in staging/prod. Not configured in local kind demo.
7. go.sum file contains representative dependency hashes. In production, run `go mod tidy && go mod download` to regenerate.

---

## 8. Cleanup

```bash
# Remove Helm releases
helm uninstall ssb-app-dev -n dev
helm uninstall ssb-app-staging -n staging

# Remove kind cluster (destroys all data)
kind delete cluster --name ssb-platform

# Remove local registry
docker rm -f kind-registry

# Remove log archives
rm -rf /tmp/ssb-logs
```
