"""Environment-driven settings. AWS credentials come from the standard boto3
chain (AWS_PROFILE locally, the Lambda execution role when deployed)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # AWS / Bedrock. Sonnet 4.6 is the default on the deployed (API Gateway, 30s
    # cap) path — materially faster per step than Opus 4.8, so agentic turns fit
    # the timeout. Swap back to global.anthropic.claude-opus-4-8 for max quality.
    aws_region: str = "us-east-1"
    bedrock_model_id: str = "global.anthropic.claude-sonnet-4-6"

    # Bedrock Guardrail (empty -> none; applied on every invocation when set)
    bedrock_guardrail_id: str = ""
    bedrock_guardrail_version: str = ""

    # Agent behaviour (guards against runaway cost/latency). The tool-call cap is
    # enforced via a Strands hook (see agent.py) to keep turns under the 30s cap.
    agent_max_tokens: int = 8000
    agent_max_tool_iterations: int = 3

    # Conversation store: empty -> in-memory (local dev); else DynamoDB table name
    conversations_table: str = ""
    conversation_ttl_days: int = 30

    # Auth (Cognito)
    auth_enabled: bool = False
    cognito_user_pool_id: str = ""
    cognito_app_client_id: str = ""

    # Toggle the AWS-Docs MCP subprocess (disabled in unit tests)
    mcp_enabled: bool = True

    port: int = 8080

    model_config = SettingsConfigDict(extra="ignore", case_sensitive=False)


settings = Settings()
