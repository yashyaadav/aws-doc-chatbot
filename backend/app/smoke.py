"""Bedrock converse smoke test.

Confirms the configured model id is invocable and that model access is granted
(an AccessDenied here means Bedrock model access must be enabled in the console).

    make smoke
"""

import sys

import boto3

from .config import settings


def main() -> int:
    client = boto3.client("bedrock-runtime", region_name=settings.aws_region)
    print(f"Invoking {settings.bedrock_model_id} in {settings.aws_region} ...")
    resp = client.converse(
        modelId=settings.bedrock_model_id,
        messages=[{"role": "user", "content": [{"text": "Reply with exactly: pong"}]}],
        inferenceConfig={"maxTokens": 20},  # Opus 4.8 rejects temperature/top_p
    )
    text = resp["output"]["message"]["content"][0]["text"].strip()
    usage = resp.get("usage", {})
    print(f"Model replied: {text!r}")
    print(f"Tokens: in={usage.get('inputTokens')} out={usage.get('outputTokens')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
