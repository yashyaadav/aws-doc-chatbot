variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "yy-awsdocs"
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "ECR image tag the Lambda runs. Build+push before the full apply."
}

variable "bedrock_model_id" {
  type    = string
  default = "global.anthropic.claude-opus-4-8"
}

variable "bedrock_resource_arns" {
  type        = list(string)
  description = "ARNs the Lambda may bedrock:InvokeModel — the global inference profile plus the foundation models it routes to."
  default = [
    "arn:aws:bedrock:us-east-1:315311531132:inference-profile/global.anthropic.claude-opus-4-8",
    "arn:aws:bedrock:*::foundation-model/anthropic.claude-opus-4-8",
  ]
}

variable "auth_enabled" {
  type    = bool
  default = true
}

variable "callback_urls" {
  type        = list(string)
  description = "Cognito Hosted UI callback URLs. Set to the CloudFront URL after the first apply, then re-apply."
  default     = ["http://localhost:8080"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:8080"]
}

variable "create_demo_user" {
  type    = bool
  default = true
}

variable "demo_username" {
  type    = string
  default = "demo@example.com"
}

variable "demo_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "budget_limit_usd" {
  type    = number
  default = 20
}

variable "alert_email" {
  type    = string
  default = ""
}
