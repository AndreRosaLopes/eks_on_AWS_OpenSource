variable "name" {
  description = "Name prefix of the platform resources and name of the EKS cluster."
  type        = string
  default     = "data-platform-dev"
}

variable "region" {
  description = "AWS Region."
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version of the EKS cluster (D-009)."
  type        = string
  default     = "1.36"
}

variable "instance_type" {
  description = "Instance type of every node group (D-007)."
  type        = string
  default     = "m7g.large"
}

variable "node_ami_release_version" {
  description = "Pinned release of the EKS optimized Amazon Linux 2023 arm64 AMI (constitution X)."
  type        = string
  default     = "1.36.4-20261003"
}

variable "data_bucket_name" {
  description = "Bucket of the platform data, created by the data root module (D-030)."
  type        = string
  default     = "data-platform-dev-data-499799893349"
}

variable "admin_principal_arns" {
  description = "Extra IAM principals of the technical team with cluster admin access (the creator always has it)."
  type        = list(string)
  default     = []
}
