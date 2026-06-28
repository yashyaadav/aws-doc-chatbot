variable "name_prefix" { type = string }

resource "aws_dynamodb_table" "conversations" {
  name         = "${var.name_prefix}-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"

  attribute {
    name = "session_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

output "table_name" { value = aws_dynamodb_table.conversations.name }
output "table_arn" { value = aws_dynamodb_table.conversations.arn }
