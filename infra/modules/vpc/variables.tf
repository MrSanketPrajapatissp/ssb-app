variable "cluster_name" {
  description = "Name of the EKS cluster. Used as prefix for all VPC resources."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets in. Recommended: 3 AZs for HA."
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway for private subnet egress."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources. Mandatory for cost attribution and governance."
  type        = map(string)
  default     = {}
}
