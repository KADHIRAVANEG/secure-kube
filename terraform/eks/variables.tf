variable "aws_region" {
  description = "AWS region for EKS deployment"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the SecureKube EKS cluster"
  type        = string
  default     = "securekube-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "Target VPC ID for EKS cluster"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Private Subnet IDs for EKS nodes"
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "EC2 instance types for hardened worker nodes"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "min_nodes" {
  description = "Minimum worker node count"
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum worker node count"
  type        = number
  default     = 5
}

variable "desired_nodes" {
  description = "Desired worker node count"
  type        = number
  default     = 3
}

variable "enable_kms_secrets_encryption" {
  description = "Enable envelope encryption of Kubernetes Secrets via AWS KMS"
  type        = bool
  default     = true
}
