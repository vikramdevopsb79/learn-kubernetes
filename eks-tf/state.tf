terraform {
  backend "s3" {
    bucket = "vikramdevopsbucket1"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}
