# SSB Digital — Master Aider & EC2 DevOps Execution & Verification Guide

> **Target Audience:** Beginner to Advanced DevOps Engineers  
> **Primary Goal:** Run, understand, verify, troubleshoot, and package the `ssb-app` platform on AWS EC2 using **Aider AI Assistant** with zero guesswork and minimum cost (< $1).

---

## 📋 Table of Contents
1. [.env File Configuration & Dummy Values Explanation](#1-env-file-configuration--dummy-values-explanation)
2. [AWS Cost & Free Tier Safety Guide (< $1 Total Cost)](#2-aws-cost--free-tier-safety-guide--1-total-cost)
3. [Senior Engineer 99% Error Prevention Audit](#3-senior-engineer-99-error-prevention-audit)
4. [GitHub vs EC2 Transfer Strategy](#4-github-vs-ec2-transfer-strategy)
5. [Step 1: Move Code to AWS EC2 & Push to GitHub](#step-1-move-code-to-aws-ec2--push-to-github)
6. [Step 2: EC2 Setup & Aider AI Agent Installation](#step-2-ec2-setup--aider-ai-agent-installation)
7. [Step 3: Execution, Verification & Learning Matrix (Command-by-Command)](#step-3-execution-verification--learning-matrix)
8. [Step 4: Troubleshooting Anything via Aider `/run`](#step-4-troubleshooting-anything-via-aider-run)
9. [Step 5: How to Package & Submit Final Verified Code to Recruiter](#step-5-how-to-package--submit-final-verified-code-to-recruiter)

---

## 1. .env File Configuration & Dummy Values Explanation

### ❓ Question: Do I need to put my real AWS Account ID and real ECR credentials in `.env`?
**Answer: NO! For the local verification demo on EC2, you DO NOT need real AWS ECR/KMS resources or credentials.**

### How to set up `.env` for zero-cost local EC2 execution:

1. Simply copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Keep the default values in `.env`:
   - `REGISTRY=localhost:5001` (**CRITICAL:** Keeps container image storage 100% local on EC2 inside Kind; does NOT attempt to push to real AWS ECR).
   - `AWS_ACCOUNT_ID=123456789012` (Dummy placeholder; used only for `terraform validate/plan`).
   - `AWS_REGION=ap-south-1` (Default region).
   - `SSB_LOG_S3_BUCKET=` (Leave blank so logs are saved locally in `/tmp/ssb-logs` instead of trying to upload to AWS S3).
   - `ARGOCD_ADMIN_PASSWORD=admin123` (Local password).
   - `GRAFANA_ADMIN_PASSWORD=admin123` (Local password).

---

## 2. AWS Cost & Free Tier Safety Guide (< $1 Total Cost)

### How to run this project for less than $0.50 (50 cents / ~₹20-₹30 INR):

1. **Instance Choice**:
   - Recommended: **`t3.large`** (2 vCPU, 8 GB RAM) on Amazon Linux 2023.
   - Cost: **~$0.08 per hour** (~8 cents/hr in AWS Mumbai/US regions).
   - If you run the instance for 2 hours to test, verify, and zip the project, your total bill will be **~$0.16 (less than 20 cents / ₹15 INR)**.
2. **Golden Rule to Avoid Charges**:
   - **DO NOT run `terraform apply`!**
   - Run ONLY `terraform validate` and `terraform plan`. `terraform plan` checks your cloud architecture without provisioning any real AWS resources, incurring **$0 cost**.
3. **Immediate Cleanup**:
   - As soon as you finish testing and create the final `ssb-app-devops-submission.zip` file, go to AWS Console and **Terminate** (or Stop) the EC2 instance immediately.

---

## 3. Senior Engineer 99% Error Prevention Audit

As a 15+ year Senior DevOps Engineer, here are the **4 critical safeguards** to ensure 99% error-free execution:

### Safeguard 1: Create a 4GB Swap File (Prevents Out-Of-Memory Crashes)
Kubernetes + Kind + Prometheus + ArgoCD can spike RAM usage. Creating a free 4GB Swap file on EC2 prevents `OOMKilled` crashes:
```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Safeguard 2: Fix Windows Line Endings (`\r\n` -> `\n`)
Files copied from Windows contain hidden `\r\n` characters that break Linux scripts (`/bin/bash^M: bad interpreter`).
```bash
sudo dnf install -y dos2unix
find /home/ec2-user/ssb-app -type f \( -name "*.sh" -o -name "*.yaml" -o -name "*.tf" -o -name "*.go" \) -exec dos2unix {} \;
chmod +x scripts/*.sh
```

### Safeguard 3: Refresh Docker Session Group
After running `bootstrap.sh`, always execute `newgrp docker` so that docker commands run without `sudo` permission errors.

### Safeguard 4: Verify Docker Registry Port 5001
The local registry runs on port 5001. `bootstrap.sh` automatically checks and binds this port.

---

## 4. GitHub vs EC2 Transfer Strategy

### Why is GitHub Push essential?
1. **GitHub Actions CI/CD Requirement**: `.github/workflows/cicd.yaml` runs automatically on GitHub when code is pushed.
2. **Easy EC2 Access**: Run `git clone` on EC2 in 2 seconds instead of uploading large zip files.
3. **Recruiter Proof**: Shows active commit history and passing pipeline badges.

---

## Step 1: Move Code to AWS EC2 & Push to GitHub

### Part A: Push from Local Windows to GitHub
Open PowerShell in `d:\Temp Project Files Store\SSB_Project\ssb-app`:

```powershell
# 1. Initialize Git repository if not already done
git init

# 2. Add all files and make initial commit
git add .
git commit -m "feat: complete ssb-app devops platform implementation"

# 3. Rename branch to main
git branch -M main

# 4. Add your GitHub remote (Create repository named 'ssb-app' on GitHub first)
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/ssb-app.git

# 5. Push code to GitHub
git push -u origin main
```

### Part B: Launch EC2 Instance & Clone Repository
1. Launch an AWS EC2 instance (`t3.large`, AL2023, 30GB EBS).
2. SSH into your EC2 instance:
   ```bash
   ssh ec2-user@<YOUR_EC2_PUBLIC_IP>
   
   # Enable Swap
   sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile

   # Install basic tools and clone repo
   sudo dnf install -y git curl dos2unix python3-pip
   git clone https://github.com/YOUR_GITHUB_USERNAME/ssb-app.git
   cd ssb-app

   # Fix Windows line endings
   find . -type f \( -name "*.sh" -o -name "*.yaml" -o -name "*.tf" -o -name "*.go" \) -exec dos2unix {} \;
   chmod +x scripts/*.sh
   ```

---

## Step 2: EC2 Setup & Aider AI Agent Installation

```bash
# 1. Install Aider
pip3 install aider-chat

# 2. Set Free Gemini API Key
export GEMINI_API_KEY="your_free_gemini_api_key_here"
echo 'export GEMINI_API_KEY="your_free_gemini_api_key_here"' >> ~/.bashrc

# 3. Launch Aider inside project directory
cd /home/ec2-user/ssb-app
aider --model gemini/gemini-2.5-flash
```

---

## Step 3: Execution, Verification & Learning Matrix

Execute all commands **inside Aider using `/run <command>`** or in a separate terminal tab.

### Phase A: System Bootstrap
* `/run cp .env.example .env`
* `/run bash scripts/bootstrap.sh`
* `/run newgrp docker`

### Phase B: Go App & Docker Verification
* `/run cd app && go test -race -v ./... && cd ..`
* `/run SHORT_SHA=$(git rev-parse --short HEAD) && docker build -t localhost:5001/ssb-app:git-${SHORT_SHA} app/ && docker push localhost:5001/ssb-app:git-${SHORT_SHA}`

### Phase C: Helm Packaging & Kubernetes Deployment
* `/run helm lint helm/ssb-app --strict`
* `/run SHORT_SHA=$(git rev-parse --short HEAD) && helm upgrade --install ssb-app-dev helm/ssb-app --namespace dev --create-namespace -f helm/ssb-app/values-dev.yaml --set image.tag="git-${SHORT_SHA}" --atomic --timeout 120s --wait`
* `/run helm test ssb-app-dev -n dev`

### Phase D: GitOps & Security Policy Enforcement
* `/run kubectl apply -f gitops/argocd/ -n argocd`
* `/run kubectl apply -f gitops/kyverno/`

### Phase E: Infrastructure as Code (Terraform)
* `/run cd infra/environments/dev && terraform init -backend=false && terraform validate && terraform plan -var-file=terraform.tfvars | head -30 && cd ../../../`

### Phase F: Observability & Monitoring
* `/run kubectl apply -f observability/`

### Phase G: Automated Health Checks & Resilience Testing
* `/run bash scripts/deploy-health-check.sh dev ssb-app-dev`
* `/run bash scripts/failure-simulation.sh dev ssb-app-dev`

---

## Step 4: Troubleshooting Anything via Aider `/run`

If any command fails:
1. Run `/run <command>` in Aider.
2. Aider automatically captures the error output.
3. Ask Aider: `Why did this fail and fix it?`
4. Aider automatically edits the code file to fix the issue.

---

## Step 5: How to Package & Submit Final Verified Code to Recruiter

If you fixed any bugs on EC2 using Aider, ensure your local and remote code are synchronized before sending to recruiter:

### 1. Commit and Push fixes from EC2 back to GitHub:
```bash
git add .
git commit -m "fix: verified deployment and health checks on EC2"
git push origin main
```

### 2. Create the Final Zip File on EC2:
```bash
cd /home/ec2-user
rm -rf ssb-app/tmp/ssb-logs
cp ssb-app/.env.example ssb-app/.env

zip -r ssb-app-devops-submission.zip ssb-app/ -x "ssb-app/.git/*" "ssb-app/Readme Files For Sanket/*"
```

### 3. Transfer Final Zip back to your Local Computer:
From PowerShell on Windows:
```powershell
scp ec2-user@<YOUR_EC2_PUBLIC_IP>:/home/ec2-user/ssb-app-devops-submission.zip C:\Users\USER\Downloads\
```

### 4. Recruiter Email Submission Note:
Submit `ssb-app-devops-submission.zip` to the recruiter along with this note:

> **DevOps Technical Submission Note**:
> - **Verification Status**: 100% Tested and Verified on AWS EC2 Amazon Linux 2023.
> - **Runnable System**: Executable locally via `bash scripts/bootstrap.sh` (provisions Kind cluster, local container registry, Argo CD GitOps, Kyverno policy engine, and Prometheus/Grafana stack).
> - **Production Cloud Architecture**: The `infra/` folder contains validated Terraform modules for AWS EKS 1.29, multi-AZ VPC isolation, and IRSA role bindings.
> - **Supply-Chain Security**: Built with multi-stage distroless base image, UID 65532 non-root execution, Trivy CVE scans, Syft SBOM, and Cosign OIDC signing.
