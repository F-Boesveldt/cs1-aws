terraform {
  backend "s3" {
    bucket       = "cs1-aws"
    key          = "cs2-persistent.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
