variable "project_name"       { type = string; default = "ssb-digital" }
variable "aws_region"          { type = string; default = "ap-south-1" }
variable "aws_account_id"      { type = string; default = "123456789012" }
variable "vpc_cidr"            { type = string; default = "10.20.0.0/16" }
variable "availability_zones"  { type = list(string); default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"] }
variable "kubernetes_version"  { type = string; default = "1.29" }
variable "kms_key_arn"         { type = string; default = "arn:aws:kms:ap-south-1:123456789012:key/mock-key-id-for-staging" }
variable "github_org"          { type = string; default = "ssb-digital" }
variable "github_repo"         { type = string; default = "ssb-app" }
