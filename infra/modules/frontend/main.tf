variable "name_prefix" { type = string }
variable "account_id" { type = string }
variable "region" { type = string }
variable "api_host" { type = string }
variable "cognito_domain" { type = string }
variable "cognito_client_id" { type = string }

locals {
  bucket_name = "${var.name_prefix}-site-${var.account_id}"

  # AWS managed policies
  caching_optimized_id      = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  caching_disabled_id       = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  all_viewer_except_host_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

# ---------- Static site bucket (private, served only via CloudFront/OAC) ----------
resource "aws_s3_bucket" "site" {
  bucket        = local.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/assets/index.html.tftpl", {
    cognito_domain = var.cognito_domain
    client_id      = var.cognito_client_id
  })
  etag = md5(templatefile("${path.module}/assets/index.html.tftpl", {
    cognito_domain = var.cognito_domain
    client_id      = var.cognito_client_id
  }))
}

# ---------- CloudFront ----------
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name_prefix}-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.name_prefix} chatbot"

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.api_host
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = local.caching_optimized_id
  }

  # Chat API: forward to the API Gateway origin, no caching.
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = false
    cache_policy_id          = local.caching_disabled_id
    origin_request_policy_id = local.all_viewer_except_host_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn }
      }
    }]
  })
}

output "cloudfront_domain" { value = aws_cloudfront_distribution.this.domain_name }
output "bucket_name" { value = aws_s3_bucket.site.id }
