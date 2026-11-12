# Learning bucket: the name is built from variables instead of hardcoded text.
resource "aws_s3_bucket" "first" {
  # Bucket names are globally unique, so the account ID is appended.
  bucket = "${local.name_prefix}-${local.account_id}-first"

  # No tags block needed: default_tags in providers.tf adds them automatically.
}
