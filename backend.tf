# Remote state: keep terraform.tfstate in S3 instead of on this laptop.
# Backend blocks cannot use variables or locals, so every value is written literally.
terraform {
  backend "s3" {
    bucket       = "url-shortener-tfstate-145050022460" # created by bootstrap/
    key          = "dev/terraform.tfstate"              # path of the state file inside the bucket
    region       = "eu-north-1"
    encrypt      = true # encrypt the state file in S3
    use_lockfile = true # S3-native state locking (Terraform 1.10+)
  }
}
