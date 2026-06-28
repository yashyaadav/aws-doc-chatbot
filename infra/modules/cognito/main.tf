variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "callback_urls" { type = list(string) }
variable "logout_urls" { type = list(string) }
variable "create_demo_user" { type = bool }
variable "demo_username" { type = string }
variable "demo_password" {
  type      = string
  sensitive = true
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.name_prefix}-users"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  # Demo: admins create users (no open self-signup).
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_domain" "this" {
  # Hosted UI domain prefix must be globally unique and cannot contain the
  # reserved words "aws", "amazon", or "cognito" (so not derived from name_prefix).
  domain       = "yydocbot-${var.account_id}"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name_prefix}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false # public SPA client

  allowed_oauth_flows                  = ["implicit", "code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # id token used as the bearer; keep its lifetime modest.
  id_token_validity      = 60
  access_token_validity  = 60
  refresh_token_validity = 1
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user" "demo" {
  count        = var.create_demo_user ? 1 : 0
  user_pool_id = aws_cognito_user_pool.this.id
  username     = var.demo_username

  attributes = {
    email          = var.demo_username
    email_verified = "true"
  }

  # Set a permanent password if provided; otherwise Cognito emails a temp one
  # (suppressed here) and the user must reset on first login.
  password       = var.demo_password != "" ? var.demo_password : null
  message_action = "SUPPRESS"
}

output "user_pool_id" { value = aws_cognito_user_pool.this.id }
output "app_client_id" { value = aws_cognito_user_pool_client.web.id }
output "hosted_ui_domain" {
  value = "${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

data "aws_region" "current" {}
