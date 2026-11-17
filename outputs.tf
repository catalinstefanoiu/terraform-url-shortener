# Outputs: values printed after `apply` and readable with `terraform output`.

output "account_id" {
  description = "AWS account ID Terraform deploys into"
  value       = local.account_id
}

output "table_name" {
  description = "Name of the DynamoDB table that stores short links"
  value       = aws_dynamodb_table.links.name
}
