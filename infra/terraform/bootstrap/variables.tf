variable "cluster_name" {
  description = "Name of the EKS cluster created by the foundation root module."
  type        = string
  default     = "data-platform-dev"
}

variable "region" {
  description = "AWS Region."
  type        = string
  default     = "us-east-2"
}

variable "repo_url" {
  description = "Public Git repository read anonymously by Argo CD (D-008)."
  type        = string
  default     = "https://github.com/AndreRosaLopes/eks_on_AWS_OpenSource"
}

variable "repo_revision" {
  description = "Branch synced by Argo CD."
  type        = string
  default     = "main"
}
