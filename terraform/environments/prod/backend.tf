terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket       = "mlops-aws-credit-risk-s3"
    key          = "prod/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
