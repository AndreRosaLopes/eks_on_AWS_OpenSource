# Persistent data bucket (D-030): applied once and never destroyed by the teardown.
terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
  }

  backend "s3" {
    bucket       = "data-platform-dev-tfstate-499799893349"
    key          = "data/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
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
