variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Pin to a specific minor version."
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster is deployed."
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs (for ELBs)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs (for EKS nodes)."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encrypting Kubernetes secrets at rest."
  type        = string
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible. Set false in production."
  type        = bool
  default     = false
}

variable "system_node_instance_types" {
  description = "EC2 instance types for system node group."
  type        = list(string)
  default     = ["m5.large"]
}

variable "system_node_desired" {
  type    = number
  default = 2
}

variable "system_node_min" {
  type    = number
  default = 1
}

variable "system_node_max" {
  type    = number
  default = 3
}

variable "app_node_instance_types" {
  description = "EC2 instance types for application node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "app_node_desired" {
  type    = number
  default = 2
}

variable "app_node_min" {
  type    = number
  default = 1
}

variable "app_node_max" {
  type    = number
  default = 10
}

variable "tags" {
  description = "Tags applied to all EKS resources."
  type        = map(string)
  default     = {}
}
