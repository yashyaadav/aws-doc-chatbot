variable "name_prefix" { type = string }
variable "region" { type = string }
variable "image_uri" { type = string }
variable "bedrock_model_id" { type = string }
variable "bedrock_resource_arns" { type = list(string) }
variable "conversations_table" { type = string }
variable "conversations_table_arn" { type = string }
variable "auth_enabled" { type = bool }
variable "cognito_user_pool_id" { type = string }
variable "cognito_app_client_id" { type = string }

locals {
  function_name = "${var.name_prefix}-api"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "perms" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
  statement {
    sid       = "Bedrock"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = var.bedrock_resource_arns
  }
  statement {
    sid       = "Dynamo"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [var.conversations_table_arn]
  }
  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "perms" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.perms.json
}

resource "aws_lambda_function" "this" {
  function_name = local.function_name
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  timeout       = 300
  memory_size   = 1024
  architectures = ["x86_64"]

  environment {
    variables = {
      BEDROCK_MODEL_ID      = var.bedrock_model_id
      CONVERSATIONS_TABLE   = var.conversations_table
      AUTH_ENABLED          = var.auth_enabled ? "true" : "false"
      COGNITO_USER_POOL_ID  = var.cognito_user_pool_id
      COGNITO_APP_CLIENT_ID = var.cognito_app_client_id
      AGENT_MAX_TOKENS      = "3000" # keep turns within the API Gateway 30s cap
      AWS_LWA_INVOKE_MODE   = "buffered"
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# NOTE: Lambda Function URLs are blocked by an org guardrail in this exam account
# (public + OAC-signed both 403), so ingress is via API Gateway instead. The
# streaming Function URL remains the preferred design in an unrestricted account.

output "function_name" { value = aws_lambda_function.this.function_name }
output "function_arn" { value = aws_lambda_function.this.arn }
output "invoke_arn" { value = aws_lambda_function.this.invoke_arn }
