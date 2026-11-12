# AWS provider configuration.
# Credentials come from ~/.aws (set up with `aws configure`), never from code.
provider "aws" {
  region = var.aws_region

  # Tags applied automatically to EVERY resource created by this provider
  default_tags {
    tags = local.common_tags
  }
}
