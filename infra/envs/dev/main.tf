data "aws_caller_identity" "current" {}

module "ecr" {
  source      = "../../modules/ecr"
  name_prefix = var.name_prefix
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  name_prefix = var.name_prefix
}

# Independent of the frontend: callback URLs come from a var (set to the
# CloudFront URL after the first apply, then re-apply) to avoid a dependency cycle.
module "cognito" {
  source           = "../../modules/cognito"
  name_prefix      = var.name_prefix
  account_id       = data.aws_caller_identity.current.account_id
  callback_urls    = var.callback_urls
  logout_urls      = var.logout_urls
  create_demo_user = var.create_demo_user
  demo_username    = var.demo_username
  demo_password    = var.demo_password
}

module "lambda" {
  source                  = "../../modules/lambda"
  name_prefix             = var.name_prefix
  region                  = var.region
  image_uri               = "${module.ecr.repository_url}:${var.image_tag}"
  bedrock_model_id        = var.bedrock_model_id
  bedrock_resource_arns   = var.bedrock_resource_arns
  conversations_table     = module.dynamodb.table_name
  conversations_table_arn = module.dynamodb.table_arn
  auth_enabled            = var.auth_enabled
  cognito_user_pool_id    = module.cognito.user_pool_id
  cognito_app_client_id   = module.cognito.app_client_id
}

# Public ingress. Lambda Function URLs are blocked by an org guardrail in this
# account, so the chat path goes through API Gateway (HTTP API → Lambda proxy).
module "apigw" {
  source               = "../../modules/apigw"
  name_prefix          = var.name_prefix
  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
}

module "frontend" {
  source            = "../../modules/frontend"
  name_prefix       = var.name_prefix
  account_id        = data.aws_caller_identity.current.account_id
  region            = var.region
  api_host          = module.apigw.api_host
  cognito_domain    = module.cognito.hosted_ui_domain
  cognito_client_id = module.cognito.app_client_id
}

module "observability" {
  source               = "../../modules/observability"
  name_prefix          = var.name_prefix
  lambda_function_name = module.lambda.function_name
  budget_limit_usd     = var.budget_limit_usd
  alert_email          = var.alert_email
}
