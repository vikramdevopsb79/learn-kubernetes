terraform {
  backend "s3" {
    bucket = "d79-terraform"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}
