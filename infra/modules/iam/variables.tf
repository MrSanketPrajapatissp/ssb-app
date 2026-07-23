variable "cluster_name" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "aws_account_id" {
  type = string
}
variable "oidc_provider_arn" {
  type = string
}
variable "oidc_provider_url" {
  type = string
}
variable "kms_key_arn" {
  type = string
}
variable "app_namespace" {
  description = "Kubernetes namespace where ssb-app runs."
  type        = string
  default     = "dev"
}
variable "github_org" {
  description = "GitHub organization name for OIDC trust policy."
  type        = string
}
variable "github_repo" {
  description = "GitHub repository name for OIDC trust policy."
  type        = string
  default     = "ssb-app"
}
variable "tags" {
  type    = map(string)
  default = {}
}
