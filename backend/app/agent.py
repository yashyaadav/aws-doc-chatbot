"""Strands agent wired to Claude on Bedrock with the AWS-Docs MCP tools."""

from strands import Agent
from strands.hooks import BeforeToolCallEvent, HookProvider, HookRegistry
from strands.models import BedrockModel

from .config import settings

SYSTEM_PROMPT = """\
You are an AWS documentation assistant. Answer questions about Amazon Web \
Services using the AWS documentation tools available to you.

Rules:
- Ground every factual claim in the AWS docs. Use the `search` tool to find \
relevant pages and the `read` tool to read them before answering. Do not answer \
AWS questions from memory when a tool can confirm the current detail.
- Be efficient with tools: do ONE focused `search`, then `read` AT MOST ONE \
(occasionally two) of the most relevant pages — never more. You are on a strict \
latency budget (a hard cap of 3 tool calls per question); spend them wisely and \
answer as soon as you have enough, rather than reading exhaustively.
- Cite the AWS documentation URL(s) you used at the end of your answer.
- Stay scoped to AWS. If a question is not about AWS, briefly say so and offer \
to help with an AWS topic instead.
- If the docs do not cover something, say what you could not find rather than \
guessing. Be concise, lead with the answer, and keep it focused — for broad \
"how do I set up X" questions, give the main path plus a short list of \
alternatives/prerequisites rather than an exhaustive walkthrough.
"""


class ToolCallCap(HookProvider):
    """Cap the number of tool calls per turn so an agentic turn can't run past
    the API Gateway 30s timeout. The call that exceeds the budget is cancelled
    with a message telling the model to answer with what it already gathered
    (graceful degradation, not a hard truncation)."""

    def __init__(self, max_calls: int):
        self.max_calls = max_calls
        self.count = 0

    def register_hooks(self, registry: HookRegistry) -> None:
        registry.add_callback(BeforeToolCallEvent, self._before)

    def _before(self, event: BeforeToolCallEvent) -> None:
        self.count += 1
        if self.count > self.max_calls:
            event.cancel_tool = (
                "Tool-call budget reached — do not call any more tools. Answer now "
                "using the documentation you have already gathered, cite those URLs, "
                "and briefly note anything you could not verify."
            )


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
        hooks=[ToolCallCap(settings.agent_max_tool_iterations)],
    )
