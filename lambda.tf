# Lambda function: the TypeScript code from app/, packaged and deployed by Terraform.

locals {
  function_name = "${local.name_prefix}-api" # url-shortener-dev-api, reused below
}

# Zip the bundled code. Run `npm run build` in app/ first, so dist/index.js exists.
data "archive_file" "lambda" {
  type             = "zip"                              # archive format
  source_file      = "${path.module}/app/dist/index.js" # the single file built by esbuild
  output_file_mode = "0666"                             # same file mode on Windows and Linux -> same hash
  output_path      = "${path.module}/build/lambda.zip"  # where the zip is written (git-ignored)
}

# Created by Terraform (not by Lambda) so logs expire and the group is managed as code.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}" # the exact name Lambda writes to
  retention_in_days = 14                                   # log events older than 14 days are deleted
}

resource "aws_lambda_function" "api" {
  function_name = local.function_name     # name shown in the console
  role          = aws_iam_role.lambda.arn # identity the code runs as (iam.tf)
  runtime       = "nodejs24.x"            # Node.js version that runs the code
  handler       = "index.handler"         # file index.js, exported function "handler"
  architectures = ["arm64"]               # Graviton: cheaper than x86
  memory_size   = 128                     # MB; CPU power grows with memory
  timeout       = 5                       # seconds before Lambda stops a request

  filename    = data.archive_file.lambda.output_path         # zip to upload
  code_sha256 = data.archive_file.lambda.output_base64sha256 # zip hash, compared with the code in AWS: changed -> redeploy

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.links.name # read in the code as process.env.TABLE_NAME
    }
  }

  # The log group must exist (with its retention) before the function first writes to it.
  depends_on = [
    aws_cloudwatch_log_group.lambda, # where the logs go
    aws_iam_role_policy.lambda       # the right to write them
  ]
}
