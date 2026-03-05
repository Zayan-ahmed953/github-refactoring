output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.this.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.this.arn
}

output "lambda_alias_name" {
  description = "Name of the Lambda alias for this environment"
  value       = aws_lambda_alias.current.name
}

output "lambda_alias_arn" {
  description = "ARN of the Lambda alias for this environment"
  value       = aws_lambda_alias.current.arn
}


