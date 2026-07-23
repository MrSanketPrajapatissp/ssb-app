# prod/main.tf — Production. HA across 3 AZs, private endpoint, larger nodes.

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  environment  = "prod"
  cluster_name = "${var.project_name}-${local.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = "ssb-digital-sre"
    CostCenter  = "engineering"
    Criticality = "high"
  }
}

module "vpc" {
  source             = "../../modules/vpc"
  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_nat_gateway = true
  tags               = local.common_tags
}

module "eks" {
  source                         = "../../modules/eks"
  cluster_name                   = local.cluster_name
  kubernetes_version             = var.kubernetes_version
  vpc_id                         = module.vpc.vpc_id
  public_subnet_ids              = module.vpc.public_subnet_ids
  private_subnet_ids             = module.vpc.private_subnet_ids
  kms_key_arn                    = var.kms_key_arn
  cluster_endpoint_public_access = false  # Private endpoint only in production.
  system_node_instance_types     = ["m5.large"]
  system_node_desired            = 3
  system_node_min                = 2
  system_node_max                = 5
  app_node_instance_types        = ["m5.xlarge"]
  app_node_desired               = 3
  app_node_min                   = 3
  app_node_max                   = 20
  tags                           = local.common_tags
}

module "iam" {
  source            = "../../modules/iam"
  cluster_name      = local.cluster_name
  aws_region        = var.aws_region
  aws_account_id    = var.aws_account_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  kms_key_arn       = var.kms_key_arn
  app_namespace     = "prod"
  github_org        = var.github_org
  github_repo       = var.github_repo
  tags              = local.common_tags
}
