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

variable "alert_email" {
  description = "Email address that receives the alarm notifications"
  type        = string
  sensitive   = true # hidden in plan/apply output (still stored in the state file)
  # No default: the value comes from terraform.tfvars, which Git ignores

  validation {
    condition     = can(regex("^[^@ ]+@[^@ ]+[.][^@ ]+$", var.alert_email)) # something@something.something
    error_message = "alert_email must look like an email address, e.g. name@example.com."
  }
}
