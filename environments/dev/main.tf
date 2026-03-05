terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

module "app_lambda" {
  source = "../../modules/lambda"

  # Lambda for the core app functionality in dev
  function_name = "app-function-dev"
  handler       = "app.lambda_handler"
  runtime       = "python3.12"

  # Match the First-time-lambda-deploy.md contract: directory-based source_path
  # Points to the app_function directory under lambda_functions
  source_path = "../../lambda_functions/app_function"

  environment = var.environment

  timeout     = 10
  memory_size = 128

  environment_variables = {
    STAGE = var.environment
  }
}

# Lambda backing the /api route in dev
module "api_lambda" {
  source = "../../modules/lambda"

  function_name = "api-function-dev"
  handler       = "new.lambda_handler"
  runtime       = "python3.12"

  # Match the First-time-lambda-deploy.md contract: directory-based source_path
  # Points to the new_function directory under lambda_functions
  source_path = "../../lambda_functions/new_function"

  environment = var.environment

  timeout     = 10
  memory_size = 128

  environment_variables = {
    STAGE = var.environment
  }
}

# Shared HTTP API that can route to one or many Lambda aliases
module "http_api" {
  source   = "../../modules/api-gateway"
  api_name = "shared-http-api-dev"

  # Start with two routes; add more entries here as you create additional Lambda modules.
  routes = {
    app_root = {
      route_key         = "GET /"
      lambda_name       = module.app_lambda.lambda_function_name
      lambda_alias_name = module.app_lambda.lambda_alias_name
      lambda_alias_arn  = module.app_lambda.lambda_alias_arn
    }
    api_root = {
      route_key         = "GET /api"
      lambda_name       = module.api_lambda.lambda_function_name
      lambda_alias_name = module.api_lambda.lambda_alias_name
      lambda_alias_arn  = module.api_lambda.lambda_alias_arn
    }
  }
}