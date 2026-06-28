"""FastAPI app: the agentic AWS-docs chat API.

Runs identically locally (uvicorn) and on Lambda (container image + AWS Lambda
Web Adapter, Function URL in RESPONSE_STREAM mode). The chat endpoint streams
tokens as Server-Sent Events.
"""

import json
import threading
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import agent as agent_mod
from .auth import AuthError, verify_token
from .config import settings
from .mcp_client import build_aws_docs_mcp_client
from .sessions import get_store

store = get_store()

# MCP tools are loaded lazily on first use (NOT at startup): spawning the stdio
# server takes several seconds, which would blow Lambda's ~10s init window and
# leave the server "not ready" when the first request arrives.
_tools = None
_mcp_client = None
_tools_lock = threading.Lock()


def ensure_tools():
    global _tools, _mcp_client
    if not settings.mcp_enabled:
        return []
    if _tools is None:
        with _tools_lock:
            if _tools is None:
                _mcp_client = build_aws_docs_mcp_client()
                _mcp_client.__enter__()
                _tools = _mcp_client.list_tools_sync()
    return _tools


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield  # server is ready immediately; MCP loads on first chat request
    if _mcp_client is not None:
        _mcp_client.__exit__(None, None, None)


app = FastAPI(title="AWS Documentation Chatbot", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tightened to the CloudFront origin via infra in M2
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    session_id: str
    message: str


async def require_user(authorization: str | None = Header(default=None)) -> dict | None:
    """Auth dependency. No-op when AUTH_ENABLED=false (local dev)."""
    if not settings.auth_enabled:
        return None
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    try:
        return verify_token(authorization.split(" ", 1)[1])
    except AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


def _extract_turns(messages: list) -> list[dict]:
    """Reduce the Strands message list to a renderable transcript: user/assistant
    turns that carry text. Tool-call and tool-result blocks (which have no text,
    e.g. fetched doc payloads) are skipped."""
    turns = []
    for m in messages:
        role = m.get("role")
        if role not in ("user", "assistant"):
            continue
        text = "".join(
            b["text"] for b in m.get("content", []) if isinstance(b.get("text"), str)
        ).strip()
        if text:
            turns.append({"role": role, "text": text})
    return turns


@app.get("/api/history")
async def history(session_id: str, _user=Depends(require_user)):
    """Prior turns for a session, so the UI can rehydrate after a page refresh."""
    return {"turns": _extract_turns(store.get(session_id))}


@app.get("/healthz")
async def healthz():
    return {
        "status": "ok",
        "mcp_ready": _tools is not None,
        "tools": len(_tools) if _tools else 0,
        "model": settings.bedrock_model_id,
    }


def _sse(data: str, event: str | None = None) -> str:
    prefix = f"event: {event}\n" if event else ""
    return f"{prefix}data: {json.dumps(data)}\n\n"


@app.post("/api/chat")
async def chat(req: ChatRequest, _user=Depends(require_user)):
    history = store.get(req.session_id)
    agent = agent_mod.build_agent(ensure_tools(), history)

    async def generate():
        try:
            async for event in agent.stream_async(req.message):
                if "data" in event:
                    yield _sse(event["data"])
            store.put(req.session_id, agent.messages)
            yield _sse("", event="done")
        except Exception as exc:  # surface errors to the client as an SSE event
            yield _sse(str(exc), event="error")

    return StreamingResponse(generate(), media_type="text/event-stream")
