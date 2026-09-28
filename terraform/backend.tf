terraform {
  backend "s3" {
    bucket       = "cs1-aws"
    key          = "cs1.terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
