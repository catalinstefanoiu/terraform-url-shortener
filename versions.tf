# Terraform and provider version constraints
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # any 6.x release, never 7.0
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8" # zips the Lambda code for upload to AWS
    }
  }
}
