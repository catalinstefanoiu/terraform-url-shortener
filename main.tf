# Terraform settings: required Terraform version and the providers this project uses
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # downloaded from registry.terraform.io
      version = " ~> 6.0"       # any 6.x release, but never 7.0 (avoids breaking changes)
    }
  }
}

# AWS provider configuration.
# Credentials are read automatically from ~/.aws (set up with `aws configure`),
# so they never appear in this code

provider "aws" {
  region = "eu-north-1"
}

# Our first resource: an S3 bucket.
# "aws_s3_bucket" is the resource TYPE (defined by the provider),
# "first" is the LOCAL NAME we use to refer to it inside Terraform.
resource "aws_s3_bucket" "first" {
  # Bucket names are globally unique across ALL AWS accounts,
  # so we include the account ID to avoid collisions.
  bucket = "tf-learning-145050022460-first"

  tags = {
    Project = "terraform-url-shortener"
    Stage   = "2"
  }
}
