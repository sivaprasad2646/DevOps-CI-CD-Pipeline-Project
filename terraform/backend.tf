terraform {
  backend "s3" {
    bucket         = "tf-state-prod-1234567890"
    key            = "eks/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "tf-locks"
  }
}
