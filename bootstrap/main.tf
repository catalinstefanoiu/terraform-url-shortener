# Bootstrap: creates the S3 bucket that stores Terraform state for the main project.
# Run ONCE, with local state: the bucket must exist before any configuration
# can keep its state in it (chicken-and-egg problem).


terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x release, never 7.0
    }
  }
}

provider "aws" {

  region = "eu-north-1"

  # Tags applied automatically to EVERY resource created by this provider
  default_tags {
    tags = {
      Project   = "url-shortener"
      ManagedBy = "terraform"
      Purpose   = "terraform-state"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = "url-shortener-tfstate-${data.aws_caller_identity.current.account_id}"

  # Refuse to destroy this bucket: losing it means losing track of all infrastructure.
  lifecycle {
    prevent_destroy = true
  }
}

# Keep every previous version of the state file, so a broken state can be restored.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest: it can contain sensitive values.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block every form of public access to the state bucket.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

