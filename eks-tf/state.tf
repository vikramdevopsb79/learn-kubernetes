terraform {
  backend "s3" {
    bucket = "vikramdevopsbucket"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}
