variable "name_prefix" { type = string }

resource "aws_ecr_repository" "this" {
  name                 = "${var.name_prefix}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # demo: allow `terraform destroy` to remove images too

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep only the most recent images to control storage cost.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 5 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.this.repository_url }
output "repository_arn" { value = aws_ecr_repository.this.arn }
output "repository_name" { value = aws_ecr_repository.this.name }
