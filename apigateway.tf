# Public HTTP API in front of the Lambda function: turns HTTP requests into Lambda events.

resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-http-api" # url-shortener-dev-http-api
  protocol_type = "HTTP"                          # HTTP API (simpler and cheaper than REST API)
}

# Where the routes send their requests: the Lambda function.
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id       # part of the API above
  integration_type       = "AWS_PROXY"                        # whole request in, function's response out unchanged
  integration_method     = "POST"                             # API Gateway calls Lambda's Invoke API, always a POST
  integration_uri        = aws_lambda_function.api.invoke_arn # invoke_arn, not arn (see Attribute Reference)
  payload_format_version = "2.0"                              # event format handler.ts expects; default is 1.0
}

resource "aws_apigatewayv2_route" "create_link" {
  api_id    = aws_apigatewayv2_api.http.id                             # part of the API above
  route_key = "POST /links"                                            # becomes event.routeKey
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}" # send to the Lambda integration
}

resource "aws_apigatewayv2_route" "redirect" {
  api_id    = aws_apigatewayv2_api.http.id                             # part of the API above
  route_key = "GET /{code}"                                            # {code} -> event.pathParameters.code
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}" # same integration
}

# $default stage: the API is served at the root URL, with no stage name in the path.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id # stage of the API above
  name        = "$default"                   # special name: no stage name in the URL
  auto_deploy = true                         # route and integration changes go live automatically

  # Public endpoint: cap the traffic so a flood of requests cannot run up the bill.
  default_route_settings {
    throttling_rate_limit  = 5  # requests per second, on average
    throttling_burst_limit = 10 # short spikes allowed above the average
  }
}

# Resource-based policy on the function: lets this API, and only this API, invoke it.
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromApiGateway"                    # label of this rule in the policy
  action        = "lambda:InvokeFunction"                        # the right to run the function
  function_name = aws_lambda_function.api.function_name          # on our function
  principal     = "apigateway.amazonaws.com"                     # granted to the API Gateway service
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*" # but only when the call comes from this API
}
