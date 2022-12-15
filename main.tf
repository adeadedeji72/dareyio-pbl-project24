provider "aws" {
region = "us-east-1"
access_key = "AKIAQRK"
secret_key = "xbMo+6UUuulcgbvE+ZKj4"
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
