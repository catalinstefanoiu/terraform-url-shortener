# Input variables: values that can change without editing the code.

variable "aws_region" {
  description = "AWS region where all resources are created"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names and in tags"
  type        = string
  default     = "url-shortener"

  validation {
    # S3 bucket names allow only lowercase letters, digits and hyphens
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name may contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}
