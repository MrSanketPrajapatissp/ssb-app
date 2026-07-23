# =============================================================
# modules/iam/main.tf
# IAM module — least-privilege roles and policies for ssb-app.
#
# Implements IRSA (IAM Roles for Service Accounts) pattern:
# Pods assume IAM roles via OIDC federation — no long-lived credentials.
# =============================================================

# IRSA role for ssb-app — read-only access to Secrets Manager.
# The app retrieves its runtime configuration from Secrets Manager
# via the External Secrets Operator, not direct SDK calls.
resource "aws_iam_role" "ssb_app" {
  name        = "${var.cluster_name}-ssb-app-role"
  description = "IRSA role for ssb-app pods. Least-privilege: read secrets only."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Restrict to the specific Kubernetes service account.
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${var.app_namespace}:ssb-app"
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# Allow ssb-app to read its specific secrets from Secrets Manager.
resource "aws_iam_policy" "ssb_app_secrets" {
  name        = "${var.cluster_name}-ssb-app-secrets-policy"
  description = "Allow ssb-app to read its secrets from AWS Secrets Manager."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:${var.cluster_name}/ssb-app/*"
        ]
      },
      {
        # Allow KMS decryption for secrets encrypted with the cluster key.
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [var.kms_key_arn]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssb_app_secrets" {
  role       = aws_iam_role.ssb_app.name
  policy_arn = aws_iam_policy.ssb_app_secrets.arn
}

# CI/CD Pipeline Role — assumed by GitHub Actions via OIDC.
# Only allows ECR push and helm deploy operations; no cluster admin.
resource "aws_iam_role" "cicd" {
  name        = "${var.cluster_name}-cicd-role"
  description = "Role for GitHub Actions CI/CD pipeline. OIDC federated."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Restrict to the specific GitHub org/repo.
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "cicd" {
  name        = "${var.cluster_name}-cicd-policy"
  description = "Least-privilege CI/CD policy: ECR push + EKS describe only."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR authentication and push.
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${var.aws_account_id}:repository/ssb-app",
          "*"  # GetAuthorizationToken requires *.
        ]
      },
      {
        # Minimal EKS access — describe cluster to get kubeconfig.
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = ["arn:aws:eks:${var.aws_region}:${var.aws_account_id}:cluster/${var.cluster_name}"]
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cicd" {
  role       = aws_iam_role.cicd.name
  policy_arn = aws_iam_policy.cicd.arn
}

# ECR Repository for ssb-app images.
resource "aws_ecr_repository" "ssb_app" {
  name                 = "ssb-app"
  image_tag_mutability = "IMMUTABLE"  # Prevents tag overwrites.

  image_scanning_configuration {
    scan_on_push = true  # Auto-scan every pushed image.
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = var.tags
}

# ECR lifecycle policy — keep only the last 30 images per branch prefix.
resource "aws_ecr_lifecycle_policy" "ssb_app" {
  repository = aws_ecr_repository.ssb_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 git-SHA tagged images."
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["git-"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 7 days."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
