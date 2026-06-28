import pytest
from fastapi.testclient import TestClient

from app import agent as agent_mod
from app import config
from app import main as main_mod


class FakeAgent:
    """Stand-in for a Strands agent: streams two chunks, records the turn."""

    def __init__(self):
        self.messages = []

    async def stream_async(self, message):
        self.messages = [
            {"role": "user", "content": [{"text": message}]},
            {"role": "assistant", "content": [{"text": "hello world"}]},
        ]
        for chunk in ("hello ", "world"):
            yield {"data": chunk}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(config.settings, "mcp_enabled", False)
    monkeypatch.setattr(config.settings, "auth_enabled", False)
    monkeypatch.setattr(agent_mod, "build_agent", lambda tools, history=None: FakeAgent())
    with TestClient(main_mod.app) as c:
        yield c


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["tools"] == 0


def test_chat_streams_and_persists(client):
    r = client.post("/api/chat", json={"session_id": "s1", "message": "hi"})
    assert r.status_code == 200
    assert "hello " in r.text and "world" in r.text
    assert "event: done" in r.text
    # the turn (user + assistant) was persisted to the session store
    assert len(main_mod.store.get("s1")) == 2


def test_auth_required_when_enabled(monkeypatch):
    monkeypatch.setattr(config.settings, "mcp_enabled", False)
    monkeypatch.setattr(config.settings, "auth_enabled", True)
    with TestClient(main_mod.app) as c:
        r = c.post("/api/chat", json={"session_id": "s", "message": "hi"})
        assert r.status_code == 401
