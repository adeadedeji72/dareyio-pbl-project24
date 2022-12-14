provider "aws" {
region = "us-east-1"
access_key = "AKIA3DAJVTPUPOECXQRK"
secret_key = "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"
}

# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }
