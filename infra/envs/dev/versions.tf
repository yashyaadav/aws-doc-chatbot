terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket         = "yy-awsdocs-tfstate-315311531132"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "yy-awsdocs-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region
  # AWS_PROFILE / creds come from the environment (assignment profile).
  default_tags {
    tags = {
      Project   = "yy-awsdocs"
      Env       = "dev"
      ManagedBy = "terraform"
    }
  }
}
