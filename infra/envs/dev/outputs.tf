output "app_url" {
  description = "Open this in a browser (after setting it as the Cognito callback and re-applying)."
  value       = "https://${module.frontend.cloudfront_domain}"
}

output "cloudfront_domain" {
  value = module.frontend.cloudfront_domain
}

output "api_host" {
  value = module.apigw.api_host
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "cognito_hosted_ui_domain" {
  value = module.cognito.hosted_ui_domain
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_app_client_id" {
  value = module.cognito.app_client_id
}

output "conversations_table" {
  value = module.dynamodb.table_name
}
