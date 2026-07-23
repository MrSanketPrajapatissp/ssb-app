variable "project_name" {
  type    = string
  default = "ssb-digital"
}
variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "aws_account_id" {
  type        = string
  description = "AWS account ID. Set via TF_VAR_aws_account_id env variable."
  default     = "123456789012"  # MOCK value for validate/plan.
}
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "availability_zones" {
  type    = list(string)
  default = ["ap-south-1a", "ap-south-1b"]
}
variable "kubernetes_version" {
  type    = string
  default = "1.29"
}
variable "kms_key_arn" {
  type        = string
  description = "ARN of KMS key for secrets encryption. MOCK for dev."
  default     = "arn:aws:kms:ap-south-1:123456789012:key/mock-key-id-for-dev"
}
variable "github_org" {
  type    = string
  default = "ssb-digital"
}
variable "github_repo" {
  type    = string
  default = "ssb-app"
}
