variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "handler" {
  description = "Handler for the Lambda function"
  type        = string
  default     = "app.lambda_handler"
}

variable "runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "source_path" {
  description = "Path to the Lambda function source directory (e.g. ../../lambda/functions/my-lambda)"
  type        = string
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 10
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 128
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, uat, prod)"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

