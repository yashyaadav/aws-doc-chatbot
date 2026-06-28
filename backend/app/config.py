"""Environment-driven settings. AWS credentials come from the standard boto3
chain (AWS_PROFILE locally, the Lambda execution role when deployed)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # AWS / Bedrock
    aws_region: str = "us-east-1"
    bedrock_model_id: str = "global.anthropic.claude-opus-4-8"

    # Agent behaviour (guards against runaway cost/latency)
    agent_max_tokens: int = 8000
    agent_max_tool_iterations: int = 8

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
