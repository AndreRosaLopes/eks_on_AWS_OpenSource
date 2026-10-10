# One-time creation of the Terraform state bucket (D-005). This root module keeps a local state.
terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.name
      Environment = "dev"
      Step        = "0"
    }
  }
}
