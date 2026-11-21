# IAM for the Lambda function: a role (who it is) plus a policy (what it may do).

# Trust policy: only the Lambda service may assume this role.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# The identity the Lambda function runs as. No password, no long-lived keys.
resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Permissions: least privilege, only the actions the code really uses.
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "ReadWriteLinks"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.links.arn] # this table only, not every table
  }

  # Write logs only to the function's own log group.
  statement {
    sid       = "WriteOwnLogs"                                # label for this rule
    effect    = "Allow"                                       # allow (everything else stays denied)
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"] # create a log stream, then write lines to it
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]  # any stream, but only in this log group
  }
}

# Inline policy: belongs to this role only and is deleted together with it.
resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name_prefix}-lambda-permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}
