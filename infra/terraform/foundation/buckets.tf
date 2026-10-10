# Tool buckets: deleted with the environment, like the rest of the tool state (D-027, D-030).
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "airflow_logs" {
  bucket        = "${var.name}-airflow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Step = "P3"
  }
}

resource "aws_s3_bucket" "airbyte" {
  bucket        = "${var.name}-airbyte-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Step = "P1"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tool" {
  for_each = {
    airflow_logs = aws_s3_bucket.airflow_logs.id
    airbyte      = aws_s3_bucket.airbyte.id
  }

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tool" {
  for_each = {
    airflow_logs = aws_s3_bucket.airflow_logs.id
    airbyte      = aws_s3_bucket.airbyte.id
  }

  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
