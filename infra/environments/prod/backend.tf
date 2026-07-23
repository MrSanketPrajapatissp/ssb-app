terraform {
  backend "s3" {
    bucket         = "ssb-digital-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    kms_key_id     = "alias/terraform-state"
    dynamodb_table = "ssb-digital-terraform-locks"
  }
}
