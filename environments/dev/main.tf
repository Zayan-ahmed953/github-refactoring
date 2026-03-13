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
  region = var.aws_region
}


locals {
  app_function_dev_config = jsondecode(file("../../lambda-configs/app-function-dev-config.json"))
  api_function_dev_config = jsondecode(file("../../lambda-configs/api-function-dev-config.json"))
}

module "app_lambda" {
  source = "../../modules/lambda"

  # Lambda for the core app functionality in dev
  function_name = local.app_function_dev_config.FunctionName
  handler       = local.app_function_dev_config.Handler
  runtime       = local.app_function_dev_config.Runtime

  # Match the First-time-lambda-deploy.md contract: directory-based source_path
  # Points to the app_function directory under lambda_functions
  source_path = "../../lambda_functions/app_function"

  environment = var.environment

  timeout     = local.app_function_dev_config.Timeout
  memory_size = local.app_function_dev_config.MemorySize

  environment_variables = local.app_function_dev_config.Environment.Variables
}

# Lambda backing the /api route in dev
module "api_lambda" {
  source = "../../modules/lambda"

  function_name = local.api_function_dev_config.FunctionName
  handler       = local.api_function_dev_config.Handler
  runtime       = local.api_function_dev_config.Runtime

  # Match the First-time-lambda-deploy.md contract: directory-based source_path
  # Points to the new_function directory under lambda_functions
  source_path = "../../lambda_functions/new_function"

  environment = var.environment

  timeout     = local.api_function_dev_config.Timeout
  memory_size = local.api_function_dev_config.MemorySize

  environment_variables = local.api_function_dev_config.Environment.Variables
}


# Shared HTTP API that can route to one or many Lambda aliases
module "http_api" {
  source   = "../../modules/api-gateway"
  api_name = "shared-http-api-dev"

  # Start with two routes; add more entries here as you create additional Lambda modules.
  routes = {
    app_root = {
      route_key         = local.app_function_dev_config.ApiGatewayPaths[1]
      lambda_name       = module.app_lambda.lambda_function_name
      lambda_alias_name = module.app_lambda.lambda_alias_name
      lambda_alias_arn  = module.app_lambda.lambda_alias_arn
    }
    api_root = {
      route_key         = local.api_function_dev_config.ApiGatewayPaths[1]
      lambda_name       = module.api_lambda.lambda_function_name
      lambda_alias_name = module.api_lambda.lambda_alias_name
      lambda_alias_arn  = module.api_lambda.lambda_alias_arn
    }
  }

}

