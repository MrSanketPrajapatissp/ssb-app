# Architecture & Platform Summary

## Purpose

This repository packages a production-grade DevOps and SRE platform around a containerized Go microservice. It is designed to provide secure, repeatable delivery from source control to Kubernetes runtime.

## Platform Building Blocks

1. **Go API service**
   - The business microservice implemented in Go.
   - Packaged as a container image for Kubernetes deployment.

2. **Container build and runtime hardening**
   - Multi-stage Docker builds reduce image size and attack surface.
   - Distroless runtime image minimizes package exposure in production.

3. **Helm v3 deployment packaging**
   - Helm charts define deploy-time Kubernetes resources and values.
   - Supports environment-specific configuration through values files and overrides.

4. **GitHub Actions CI/CD**
   - Automates build, test, image publishing, and delivery workflows.
   - Integrates supply-chain and image security checks (for example signing/scanning).

5. **Argo CD GitOps delivery**
   - Synchronizes Kubernetes state from declarative manifests stored in Git.
   - Enables auditable, pull-based deployment and drift correction.

6. **Kyverno policy enforcement**
   - Adds Kubernetes admission-time security and governance controls.
   - Enforces baseline guardrails for workloads and cluster resources.

7. **Terraform-based AWS EKS infrastructure**
   - Provisions and manages AWS/EKS infrastructure as code.
   - Supports repeatable environment creation and controlled lifecycle changes.

8. **Prometheus & Grafana observability**
   - Prometheus rules define alerting and service health signals.
   - Grafana dashboards provide service and platform visualization.

## End-to-End Delivery Flow

1. Developers push changes to GitHub.
2. GitHub Actions executes CI, security checks, and artifact workflows.
3. Deployment manifests/charts are updated in Git.
4. Argo CD reconciles cluster state from the Git source of truth.
5. Kyverno validates workload/policy compliance during admission.
6. Prometheus and Grafana provide runtime telemetry, SLO visibility, and alerting.

## Operational Outcomes

- **Security-first defaults** through distroless images, policy enforcement, and CI security controls.
- **Declarative operations** via Helm, Terraform, and GitOps-managed Kubernetes state.
- **Auditability and traceability** across code, infrastructure, policy, and deployments.
- **Observability-driven reliability** with metrics, dashboards, and alert rules for fast incident response.
