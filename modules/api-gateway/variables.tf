variable "api_name" {
  description = "Name of the shared HTTP API Gateway"
  type        = string
}

variable "routes" {
  description = "Map of logical name -> route and Lambda alias configuration"
  type = map(object({
    route_key         = string  # e.g. \"GET /hello\"
    lambda_name       = string  # function name without alias
    lambda_alias_name = string  # alias name, e.g. \"dev\"
    lambda_alias_arn  = string  # full alias ARN for integration_uri
  }))
}