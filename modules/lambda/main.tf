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

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = var.source_path
  output_path = "${path.module}/build/${var.function_name}.zip"
}
resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = var.handler
  runtime       = var.runtime

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  publish = true

  timeout     = var.timeout
  memory_size = var.memory_size

  # Environment variables for the function (non-secret)
  environment {
    variables = var.environment_variables
  }
}

resource "aws_lambda_alias" "current" {
  name             = var.environment
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version
}


