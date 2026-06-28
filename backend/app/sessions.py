"""Conversation history persistence.

Lambda is stateless, so chat history lives in DynamoDB keyed by session id
(one item per session, the full Strands message list as JSON, with a TTL).
For local dev with no table configured, an in-memory store is used instead.
"""

import json
import time

import boto3

from .config import settings


class InMemoryStore:
    def __init__(self) -> None:
        self._data: dict[str, list] = {}

    def get(self, session_id: str) -> list:
        return list(self._data.get(session_id, []))

    def put(self, session_id: str, messages: list) -> None:
        self._data[session_id] = list(messages)


class DynamoStore:
    def __init__(self, table_name: str) -> None:
        self._table = boto3.resource("dynamodb", region_name=settings.aws_region).Table(table_name)

    def get(self, session_id: str) -> list:
        item = self._table.get_item(Key={"session_id": session_id}).get("Item")
        if not item:
            return []
        return json.loads(item["messages"])

    def put(self, session_id: str, messages: list) -> None:
        ttl = int(time.time()) + settings.conversation_ttl_days * 86400
        self._table.put_item(
            Item={
                "session_id": session_id,
                "messages": json.dumps(messages, default=str),
                "ttl": ttl,
            }
        )


def get_store():
    if settings.conversations_table:
        return DynamoStore(settings.conversations_table)
    return InMemoryStore()
