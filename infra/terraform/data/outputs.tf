output "data_bucket_name" {
  description = "Bucket of the platform data."
  value       = aws_s3_bucket.data.bucket
}

output "data_bucket_arn" {
  description = "ARN of the bucket of the platform data."
  value       = aws_s3_bucket.data.arn
}
