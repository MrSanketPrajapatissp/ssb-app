terraform {
  # S3 backend for remote state storage.
  # DESIGN-ONLY: This backend requires real S3 bucket and DynamoDB table.
  # For local validate/plan, run: terraform init -backend=false
  #
  # State strategy:
  #   - Separate state file per environment (dev/staging/prod).
  #   - S3 bucket with versioning enabled for state history.
  #   - DynamoDB for state locking to prevent concurrent applies.
  #   - KMS encryption for state at rest.
  #   - Bucket public access blocked.
  #   - Access controlled via IAM policies (no bucket-level ACLs).
  backend "s3" {
    bucket         = "ssb-digital-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = "ssb-digital-terraform-locks"
    # Role assumed for backend operations — CI/CD uses OIDC, humans use SSO.
    # role_arn       = "arn:aws:iam::123456789012:role/ssb-terraform-backend-role"
  }
}
