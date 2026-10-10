output "state_bucket_name" {
  description = "Bucket that holds the state of the data, foundation and bootstrap root modules."
  value       = aws_s3_bucket.state.bucket
}
