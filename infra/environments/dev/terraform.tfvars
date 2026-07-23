# Dev environment variable values — safe defaults, mocked for validate/plan.
# Do NOT put real account IDs, KMS ARNs, or credentials here.
project_name       = "ssb-digital"
aws_region         = "ap-south-1"
aws_account_id     = "123456789012"
vpc_cidr           = "10.10.0.0/16"
availability_zones = ["ap-south-1a", "ap-south-1b"]
kubernetes_version = "1.29"
kms_key_arn        = "arn:aws:kms:ap-south-1:123456789012:key/mock-key-id-for-dev"
github_org         = "ssb-digital"
github_repo        = "ssb-app"
