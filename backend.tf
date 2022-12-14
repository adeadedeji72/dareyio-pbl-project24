terraform {
  backend "s3" {
    bucket         = "bayo-project24-bucket"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
