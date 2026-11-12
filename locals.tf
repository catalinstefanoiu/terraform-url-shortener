# Look up the identity Terraform runs as (account ID, user ARN).
# A data source only READS existing information; it never creates anything.

data "aws_caller_identity" "current" {}

# Local values: computed once, reused everywhere in the configuration.
locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
