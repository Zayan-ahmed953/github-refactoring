resource "aws_apigatewayv2_api" "http_api" {
  name          = var.api_name
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda" {
  for_each              = var.routes
  api_id                = aws_apigatewayv2_api.http_api.id
  integration_type      = "AWS_PROXY"
  integration_method    = "POST"
  payload_format_version = "2.0"
  integration_uri       = each.value.lambda_alias_arn
}

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = each.value.route_key
  target    = "integrations/${aws_apigatewayv2_integration.lambda[each.key].id}"
}

resource "aws_lambda_permission" "allow_apigw_invoke" {
  for_each = var.routes

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_name
  qualifier     = each.value.lambda_alias_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
