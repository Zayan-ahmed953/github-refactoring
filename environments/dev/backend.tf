# terraform {
#   backend "s3" {
#     # Per First-time-lambda-deploy.md and README: dedicated S3 bucket per environment
#     bucket = "myorg-terraform-state-dev-yoyo" # adjust to your actual dev state bucket name
#     key    = "environments/dev/terraform.tfstate"
#     region = "us-east-1"                 # adjust to your dev region
#     encrypt = true
#   }
# }

