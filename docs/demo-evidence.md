# Demo Evidence Guide

This document describes the expected terminal output for each demo step.
On the EC2 instance, run each command and capture the output.

---

## Step 1: Build & Push Image

```
$ SHORT_SHA=$(git rev-parse --short HEAD)
$ docker build -t localhost:5001/ssb-app:git-${SHORT_SHA} app/

[+] Building 45.2s (12/12) FINISHED
 => [internal] load build definition from Dockerfile
 => [builder 1/5] FROM golang:1.22.3-alpine3.20@sha256:...
 => [builder 3/5] COPY go.mod go.sum ./
 => [builder 4/5] RUN go mod download && go mod verify
 => [builder 5/5] RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags ...
 => [stage-1 1/1] COPY --from=builder --chown=nonroot:nonroot /build/ssb-app ./ssb-app
 => exporting to image

$ docker push localhost:5001/ssb-app:git-${SHORT_SHA}
The push refers to repository [localhost:5001/ssb-app]
git-a1b2c3d4: digest: sha256:abc123... size: 527
```

---

## Step 2: Go Tests

```
$ cd app && go test -race -v ./...
=== RUN   TestHealthEndpoint
--- PASS: TestHealthEndpoint (0.00s)
=== RUN   TestReadyEndpoint
--- PASS: TestReadyEndpoint (0.00s)
=== RUN   TestMetricsEndpoint
--- PASS: TestMetricsEndpoint (0.00s)
=== RUN   TestNotFound
--- PASS: TestNotFound (0.00s)
=== RUN   TestHealthResponseStruct
--- PASS: TestHealthResponseStruct (0.00s)
PASS
ok  	github.com/ssb-digital/ssb-app	0.021s
```

---

## Step 3: Helm Lint

```
$ helm lint helm/ssb-app --strict
==> Linting helm/ssb-app
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint helm/ssb-app -f helm/ssb-app/values-dev.yaml --strict
==> Linting helm/ssb-app
1 chart(s) linted, 0 chart(s) failed
```

---

## Step 4: Deploy to Dev

```
$ helm upgrade --install ssb-app-dev helm/ssb-app \
    -n dev --create-namespace \
    -f helm/ssb-app/values-dev.yaml \
    --set image.tag="git-a1b2c3d4" \
    --atomic --timeout 120s --wait

Release "ssb-app-dev" does not exist. Installing it now.
NAME: ssb-app-dev
LAST DEPLOYED: Wed Jul 23 12:10:00 2026
NAMESPACE: dev
STATUS: deployed
REVISION: 1
NOTES:
Thank you for installing ssb-app v1.0.0!
...
```

---

## Step 5: Smoke Test

```
$ curl -s http://localhost:8080/health | python3 -m json.tool
{
    "status": "ok",
    "version": "1.0.0",
    "commit": "a1b2c3d4",
    "timestamp": "2026-07-23T12:10:15Z"
}

$ curl -s http://localhost:8080/ready | python3 -m json.tool
{
    "status": "ready",
    "version": "1.0.0",
    "commit": "a1b2c3d4",
    "timestamp": "2026-07-23T12:10:16Z"
}

$ curl -s http://localhost:8080/metrics | head -10
# HELP ssb_app_build_info Build information about the running ssb-app instance.
# TYPE ssb_app_build_info gauge
ssb_app_build_info{build_time="2026-07-23T12:00:00Z",commit="a1b2c3d4",version="1.0.0"} 1
# HELP ssb_app_http_request_duration_seconds HTTP request duration in seconds
# TYPE ssb_app_http_request_duration_seconds histogram
```

---

## Step 6: Health Check Script

```
$ bash scripts/deploy-health-check.sh dev ssb-app-dev
==============================================
 SSB App Deployment Health Check
 Namespace:    dev
 Release:      ssb-app-dev
 Timestamp:    2026-07-23T12:11:00Z
==============================================

Check 1: Deployment exists
[PASS]  Deployment 'ssb-app-dev' found in namespace 'dev'

Check 2: Replica readiness
       Desired replicas:   1
       Ready replicas:     1
       Available replicas: 1
[PASS]  All 1 replicas are ready.

Check 3: Individual pod status
[PASS]  Pod ssb-app-dev-7d8f9b-xvz4k: Running, Ready (restarts: 0)

Check 4: Service endpoint connectivity
[PASS]  /health returned HTTP 200
[PASS]  /ready returned HTTP 200
[PASS]  /metrics returned HTTP 200 (3 ssb_app_* metrics)

Check 5: HPA status
       HPA not found — autoscaling disabled (expected in dev).

Check 6: PodDisruptionBudget
       PDB not found (expected in staging/prod).

Check 7: Recent warning events
[PASS]  No recent warning events for release 'ssb-app-dev'.

Check 8: Helm release status
[PASS]  Helm release status: deployed

==============================================
RESULT: All checks passed. Deployment is healthy.
==============================================
```

---

## Step 7: Failure Simulation

```
$ bash scripts/failure-simulation.sh dev ssb-app-dev

══════════════════════════════════════════
  SCENARIO: Pre-flight Check
══════════════════════════════════════════

[INFO]  Verifying ssb-app is healthy before starting failure simulation...
[INFO]  Current Helm revision: 1
[INFO]  Pre-flight passed: 1/1 pods ready. Revision 1.

══════════════════════════════════════════
  SCENARIO: 1: Bad Image Tag (non-existent image)
══════════════════════════════════════════

[INFO]  INJECT: Deploying with non-existent image tag 'bad-tag-does-not-exist'...
[INFO]  Using 'helm upgrade --atomic' which auto-rolls back on failure.

Error: UPGRADE FAILED: timed out waiting for the condition
    (pods failed readiness: ImagePullBackOff)

[INFO]  DETECTED: Helm upgrade failed as expected (bad image).
[INFO]  RECOVERY: --atomic flag triggered automatic rollback.
[INFO]  Revision before: 1 | After attempted upgrade: 1
[INFO]  Deployment ready replicas after rollback: 1

[INFO]  --- POST-INCIDENT NOTE (Scenario 1) ---
[INFO]  Root cause: CI pipeline pushed an incorrect image tag.
[INFO]  Detection: helm --atomic detected ImagePullBackOff within 60s timeout.
[INFO]  Recovery: --atomic triggered automatic rollback to revision 1.
[INFO]  Action: Verify CI image-tag injection step; add pre-deploy image existence check.
[INFO]  Time to detection: ~30s. Time to recovery: ~90s.
[INFO]  SLO impact: Zero user impact (new pods never received traffic).

══════════════════════════════════════════
  SCENARIO: 2: Manual Rollback
══════════════════════════════════════════

[INFO]  Marking current revision 1 as our 'stable' release.
[INFO]  New revision deployed: 2
[INFO]  INJECT: Simulating discovery of a production issue with rev 2...
[WARN]  Initiating rollback to revision 1...

Rollback was a success! Happy Helming!

[INFO]  RECOVERY: Helm rollback complete. Current revision: 2
[INFO]  Waiting for rollout: deployment/ssb-app-dev (timeout 90s)...
deployment.apps/ssb-app-dev successfully rolled out

[INFO]  --- POST-INCIDENT NOTE (Scenario 2) ---
[INFO]  Root cause: Simulated post-deploy regression.
[INFO]  Recovery: 'helm rollback' executed. Pods serving traffic within 60s.
[INFO]  RTO achieved: ~90 seconds.

══════════════════════════════════════════
  SCENARIO: 3: Recovery Verification
══════════════════════════════════════════

[PASS]  All checks passed. Deployment is healthy.
[INFO]  All failure simulations completed successfully.
[INFO]  Service is fully recovered and healthy.
```

---

## Step 8: Monitored Service (Grafana)

```
$ kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
# Access: http://localhost:3000
# Login: admin / admin
# Dashboard: "SSB App — Service Dashboard"
#
# Expected panels:
#   - Request Rate: ~0.05 RPS (from health checks)
#   - Error Rate: 0%
#   - P99 Latency: < 10ms (local cluster)
#   - Ready Pods: 1
```

---

## Step 9: Terraform Validate

```
$ cd infra/environments/dev
$ terraform init -backend=false

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.55"...
- Finding hashicorp/tls versions matching "~> 4.0"...
- Installed hashicorp/aws v5.57.0

Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.

$ terraform plan -var-file=terraform.tfvars 2>&1 | tail -5
Plan: 32 to add, 0 to change, 0 to destroy.

Note: Objects have changed outside of Terraform
(This plan was generated without a state file — design-only mode)
```
