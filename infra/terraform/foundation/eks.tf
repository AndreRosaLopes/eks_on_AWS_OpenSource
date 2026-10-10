module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # D-006: public endpoint (IAM + RBAC) and private endpoint for the nodes.
  endpoint_public_access  = true
  endpoint_private_access = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for arn in var.admin_principal_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Encryption and control plane logs only where they add no cost (FR-005).
  create_kms_key              = false
  encryption_config           = null
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  # Single node role (D-004): no IAM roles for service accounts.
  enable_irsa = false

  # D-015: core add-ons, pinned (constitution X).
  addons = {
    vpc-cni = {
      addon_version  = "v1.23.2-eksbuild.1"
      before_compute = true
    }
    kube-proxy = {
      addon_version  = "v1.36.0-eksbuild.45"
      before_compute = true
    }
    coredns = {
      addon_version = "v1.14.7-eksbuild.11"
    }
    aws-ebs-csi-driver = {
      addon_version = "v1.66.0-eksbuild.1"
    }
  }

  eks_managed_node_groups = {
    # Always-on workloads (D-001).
    base = {
      ami_type                       = "AL2023_ARM_64_STANDARD"
      ami_release_version            = var.node_ami_release_version
      use_latest_ami_release_version = false
      instance_types                 = [var.instance_type]
      capacity_type                  = "ON_DEMAND"
      min_size                       = 1
      desired_size                   = 1
      max_size                       = 3

      create_iam_role = false
      iam_role_arn    = aws_iam_role.node.arn

      # Pods use the node role through the instance metadata (D-004).
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }

    # Batch workloads only: Trino workers, Airflow task pods, Airbyte job pods (D-001, D-022).
    spot = {
      ami_type                       = "AL2023_ARM_64_STANDARD"
      ami_release_version            = var.node_ami_release_version
      use_latest_ami_release_version = false
      instance_types                 = [var.instance_type]
      capacity_type                  = "SPOT"
      min_size                       = 0
      desired_size                   = 0
      max_size                       = 6

      create_iam_role = false
      iam_role_arn    = aws_iam_role.node.arn

      labels = {
        capacity = "spot"
      }
      taints = {
        spot = {
          key    = "capacity"
          value  = "spot"
          effect = "NO_SCHEDULE"
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }
    }
  }

  # Tags also reach the instances and volumes of the node groups (cost allocation, D-023).
  tags = local.tags
}
