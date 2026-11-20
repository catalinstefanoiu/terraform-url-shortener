# DynamoDB table that maps short codes to long URLs.

resource "aws_dynamodb_table" "links" {
  name         = "${local.name_prefix}-links"
  billing_mode = "PAY_PER_REQUEST" # pay per read/write, no capacity to manage
  hash_key     = "code"            # partition key: every item is looked up by its short code


  # Only key attributes are declared here; other fields (url, created_at)
  # are added by the application without any Schema.
  attribute {
    name = "code"
    type = "S" # S = string
  }

  # Continuous backups: restore the table to any second in the last 35 days.
  point_in_time_recovery {
    enabled = true
  }
}
