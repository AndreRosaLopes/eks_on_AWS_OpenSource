# Exception to D-004 (D-033): the Airbyte S3 Data Lake destination requires a static AWS access key
# with the Polaris catalog. A dedicated IAM user limited to the data bucket; the key lives only in
# the Terraform state and in a cluster Secret.
data "aws_caller_identity" "current" {}

locals {
  data_bucket_arn = "arn:aws:s3:::${var.cluster_name}-data-${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_user" "airbyte_iceberg_writer" {
  name = "${var.cluster_name}-airbyte-iceberg-writer"
}

data "aws_iam_policy_document" "airbyte_iceberg_writer" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [local.data_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.data_bucket_arn}/*"]
  }
}

resource "aws_iam_user_policy" "airbyte_iceberg_writer" {
  name   = "data-bucket"
  user   = aws_iam_user.airbyte_iceberg_writer.name
  policy = data.aws_iam_policy_document.airbyte_iceberg_writer.json
}

resource "aws_iam_access_key" "airbyte_iceberg_writer" {
  user = aws_iam_user.airbyte_iceberg_writer.name
}

resource "kubernetes_secret_v1" "airbyte_iceberg_writer" {
  metadata {
    name      = "airbyte-iceberg-writer"
    namespace = kubernetes_namespace_v1.platform["airbyte"].metadata[0].name
  }

  data = {
    access_key_id     = aws_iam_access_key.airbyte_iceberg_writer.id
    secret_access_key = aws_iam_access_key.airbyte_iceberg_writer.secret
  }
}
