output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "airflow_logs_bucket_name" {
  value = aws_s3_bucket.airflow_logs.bucket
}

output "airbyte_bucket_name" {
  value = aws_s3_bucket.airbyte.bucket
}

output "data_bucket_name" {
  value = var.data_bucket_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}
