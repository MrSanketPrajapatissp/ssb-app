# =============================================================
# infra/environments/dev/main.tf
# Dev environment — wires together VPC, EKS, and IAM modules.
# DESIGN-ONLY: Run terraform validate / plan with mocks only.
#              Never terraform apply — no real cloud cost.
# =============================================================

terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.55"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # MOCK: In production, use IRSA or IAM Identity Center.
  # For validate/plan only, no credentials are required.
  # Uncomment and set via environment variables:
  # access_key = var.aws_access_key  # From: $AWS_ACCESS_KEY_ID
  # secret_key = var.aws_secret_key  # From: $AWS_SECRET_ACCESS_KEY

  default_tags {
    tags = local.common_tags
  }
}

locals {
  environment  = "dev"
  cluster_name = "${var.project_name}-${local.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = "ssb-digital-sre"
    CostCenter  = "engineering"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name                   = local.cluster_name
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = module.vpc.vpc_id
  public_subnet_ids              = module.vpc.public_subnet_ids
  private_subnet_ids             = module.vpc.private_subnet_ids
  kms_key_arn                    = var.kms_key_arn
  cluster_endpoint_public_access = true  # OK for dev; false in prod.

  # Dev: smaller instance types to minimize cost.
  system_node_instance_types = ["t3.medium"]
  system_node_desired        = 1
  system_node_min            = 1
  system_node_max            = 2

  app_node_instance_types = ["t3.small"]
  app_node_desired        = 1
  app_node_min            = 1
  app_node_max            = 3

  tags = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  cluster_name      = local.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = var.aws_account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  kms_key_arn       = var.kms_key_arn
  app_namespace     = "dev"
  github_org        = var.github_org
  github_repo       = var.github_repo
  tags              = local.common_tags
}
