provider "aws" {
  region = var.region

  # Cost allocation tags (D-023); resources of later steps override `Step`.
  default_tags {
    tags = local.tags
  }
}

locals {
  tags = {
    Project     = var.name
    Environment = "dev"
    Step        = "0"
  }
}
