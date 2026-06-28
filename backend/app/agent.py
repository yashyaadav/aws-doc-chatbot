"""Strands agent wired to Claude on Bedrock with the AWS-Docs MCP tools."""

from strands import Agent
from strands.models import BedrockModel

from .config import settings

SYSTEM_PROMPT = """\
You are an AWS documentation assistant. Answer questions about Amazon Web \
Services using the AWS documentation tools available to you.

Rules:
- Ground every factual claim in the AWS docs. Use the `search` tool to find \
relevant pages and the `read` tool to read them before answering. Do not answer \
AWS questions from memory when a tool can confirm the current detail.
- Cite the AWS documentation URL(s) you used at the end of your answer.
- Stay scoped to AWS. If a question is not about AWS, briefly say so and offer \
to help with an AWS topic instead.
- If the docs do not cover something, say what you could not find rather than \
guessing. Be concise and lead with the answer.
"""


def build_model() -> BedrockModel:
    kwargs = dict(
        model_id=settings.bedrock_model_id,
        region_name=settings.aws_region,
        max_tokens=settings.agent_max_tokens,
    )
    # Attach the Bedrock Guardrail when configured so every invocation is
    # screened (AWS-topic scoping, content filters, PII redaction).
    if settings.bedrock_guardrail_id and settings.bedrock_guardrail_version:
        kwargs.update(
            guardrail_id=settings.bedrock_guardrail_id,
            guardrail_version=settings.bedrock_guardrail_version,
            guardrail_trace="enabled",
        )
    return BedrockModel(**kwargs)


def build_agent(tools, history=None) -> Agent:
    """Construct a per-request agent seeded with prior conversation turns.

    ``callback_handler=None`` disables Strands' default stdout printing — we
    stream tokens to the client ourselves.
    """
    return Agent(
        model=build_model(),
        tools=tools,
        system_prompt=SYSTEM_PROMPT,
        messages=history or [],
        callback_handler=None,
    )
