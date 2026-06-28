variable "name_prefix" { type = string }

# Bedrock Guardrail: keeps the assistant scoped to AWS topics, blocks unsafe
# content, and redacts PII the model might echo back from a question. Applied on
# every Bedrock invocation by the agent (see backend/app/agent.py).
resource "aws_bedrock_guardrail" "this" {
  name                      = "${var.name_prefix}-guardrail"
  description               = "Scope answers to AWS topics; block unsafe content; redact PII."
  blocked_input_messaging   = "I can only help with Amazon Web Services questions. Please ask about an AWS topic."
  blocked_outputs_messaging = "I can only help with Amazon Web Services questions. Please ask about an AWS topic."

  # Off-topic guidance: this is a docs assistant, not a source of professional advice.
  topic_policy_config {
    topics_config {
      name       = "ProfessionalAdvice"
      type       = "DENY"
      definition = "Requests for legal, medical, financial, or investment advice unrelated to operating AWS services."
      examples = [
        "Should I invest my savings in this stock?",
        "What medication should I take for a headache?",
        "Draft a legally binding contract for my business.",
      ]
    }
  }

  # Standard content filters at medium+ strength.
  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "HIGH"
      output_strength = "HIGH"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    # Defends the agent's system prompt against jailbreak / prompt-injection.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE" # PROMPT_ATTACK only applies to input
    }
  }

  # Redact obvious secrets/PII so they never reach the model or the logs.
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "AWS_SECRET_KEY"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "BLOCK"
    }
  }
}

# A published version is required to apply the guardrail at invoke time
# (DRAFT is mutable; the version pins an immutable snapshot).
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Published by terraform"
}

output "guardrail_id" { value = aws_bedrock_guardrail.this.guardrail_id }
output "guardrail_arn" { value = aws_bedrock_guardrail.this.guardrail_arn }
output "guardrail_version" { value = aws_bedrock_guardrail_version.this.version }
