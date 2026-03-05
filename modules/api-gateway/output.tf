output "api_id" {
  description = "ID of the HTTP API"
  value       = aws_apigatewayv2_api.http_api.id
}

output "invoke_url" {
  description = "Base invoke URL for the HTTP API default stage"
  value       = aws_apigatewayv2_stage.default.invoke_url
}


