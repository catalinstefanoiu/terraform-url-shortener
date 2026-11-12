# Outputs: values printed after `apply` and readable with `terraform output`.

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.first.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.first.arn
}

output "account_id" {
  description = "AWS account ID Terraform deploys into"
  value       = local.account_id
}
