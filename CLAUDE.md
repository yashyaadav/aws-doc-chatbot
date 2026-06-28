# CLAUDE.md — agent notes for this repo

## What this is
Agentic AWS-docs chatbot: Strands agent + Claude Opus 4.8 (Bedrock) + awslabs AWS-Documentation
MCP server, served as a streaming serverless web app, all in Terraform. See
[docs/architecture.md](docs/architecture.md) and [the plan](../../.claude/plans/) for full rationale.

## Environment / account
- Shared **AllCloud exam account `315311531132`**, region **us-east-1**, AWS profile **`assignment`**.
- ⚠️ Multi-tenant: **only touch resources you created.** Namespace everything `yy-awsdocs-*`.
  Terraform state lives in `yy-awsdocs-tfstate-315311531132` (our own bucket — not the shared one).
- Model: `global.anthropic.claude-opus-4-8` (global inference profile). **No `temperature`/`top_p`**
  on this model family — they 400. Use `max_tokens` / `effort` only.

## Backend (`backend/`)
- One FastAPI app (`app/main.py`) runs both locally (uvicorn) and on Lambda (container + AWS Lambda
  Web Adapter, Function URL `RESPONSE_STREAM`). Chat streams as SSE.
- `app/agent.py` builds the Strands agent; `app/mcp_client.py` launches the MCP server via
  `python -m awslabs.aws_documentation_mcp_server.server` (PATH-independent).
- `app/sessions.py` = DynamoDB or in-memory history; `app/auth.py` = Cognito JWT verify
  (`AUTH_ENABLED=false` locally); `app/config.py` = env settings; `app/smoke.py` = Bedrock check.

## Commands
- `make install` · `make smoke` · `make dev` · `make test` · `make lint` · `make fmt`
- `make tf-init|tf-plan|tf-apply|tf-destroy` (infra)
- Always load env first: handled by the Makefile (`set -a; source .env`).

## Conventions
- Keep the dual local/Lambda code path single (FastAPI app); don't fork a separate Lambda handler.
- Add cost/latency guards to any new agent path (`AGENT_MAX_TOKENS`, tool-iteration cap).
- Docker: PATH includes the Docker.app creds-helper (set in the Makefile) for builds/ECR pushes.
