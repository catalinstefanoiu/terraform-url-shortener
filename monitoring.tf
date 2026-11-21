# Monitoring: an email when the Lambda function starts failing.

# A mailbox where the alerts are published, each subscriber receives a copy.
resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts" # url-shortener-dev-alerts
}

# Email subscriber: AWS first sends a confirmation email; nothing arrives until you click the link.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn # subscribe to the topic above
  protocol  = "email"                  # deliver as a plain email
  endpoint  = var.alert_email          # the address, from terraform.tfvars (not in Git)
}

# Alarm: watches the function's Errors metric and notifies the topic.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name        = "${local.name_prefix}-lambda-errors"               # url-shortener-dev-lambda-errors
  alarm_description = "The API Lambda function threw at least one error" # shown in the email

  namespace   = "AWS/Lambda" # metrics that Lambda publishes by itself
  metric_name = "Errors"     # invocations that ended in an error (not 400/404 responses)
  dimensions = {
    FunctionName = aws_lambda_function.api.function_name # only our function
  }

  statistic           = "Sum"                           # add up the errors in each period
  period              = 60                              # period length, in seconds
  evaluation_periods  = 1                               # one bad period is enough
  comparison_operator = "GreaterThanOrEqualToThreshold" # Sum >= threshold
  threshold           = 1                               # at least 1 error
  treat_missing_data  = "notBreaching"                  # no traffic = OK, not "insufficient data"

  alarm_actions = [aws_sns_topic.alerts.arn] # email when it goes into ALARM
  ok_actions    = [aws_sns_topic.alerts.arn] # email when it is back to OK
}
