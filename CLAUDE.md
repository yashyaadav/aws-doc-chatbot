# CLAUDE.md — agent notes for this repo

## What this is
Agentic AWS-docs chatbot: Strands agent + Claude Opus 4.8 (Bedrock) + awslabs AWS-Documentation
MCP server, served as a streaming serverless web app, all in Terraform. See
[docs/architecture.md](docs/architecture.md) and [the plan](../../.claude/plans/) for full rationale.

## Environment / account
- Shared **AllCloud exam account `315311531132`**, region **us-east-1**, AWS profile **`assignment`**.
- ⚠️ Multi-tenant: **only touch resources you created.** Namespace everything `yy-awsdocs-*`.
  Terraform state lives in `yy-awsdocs-tfstate-315311531132` (our own bucket — not the shared one).
- Model: deployed default `global.anthropic.claude-sonnet-4-6` (faster, fits the API Gateway 30s cap);
  `global.anthropic.claude-opus-4-8` is a one-var swap (`bedrock_model_id`), IAM allows both. **No
  `temperature`/`top_p`** on this model family — they 400. Use `max_tokens` / `effort` only.
- Latency guards on the deployed path: hard cap of **3 tool calls/turn** (Strands `BeforeToolCallEvent`
  hook in `agent.py`), `AGENT_MAX_TOKENS=2000`, 2048 MB Lambda. Broad agentic turns must finish <30s.

## Backend (`backend/`)
- One FastAPI app (`app/main.py`) runs both locally (uvicorn) and on Lambda (container + AWS Lambda
  Web Adapter). Chat streams SSE locally; deployed ingress is **CloudFront → API Gateway → Lambda**
  (buffered) because this account's org guardrail blocks Lambda Function URLs. MCP tools load lazily
  on first request (not in lifespan) to stay within Lambda's init window.
- `app/agent.py` builds the Strands agent; `app/mcp_client.py` launches the MCP server via
  `python -m awslabs.aws_documentation_mcp_server.server` (PATH-independent).
- `app/sessions.py` = DynamoDB or in-memory history; `app/auth.py` = Cognito JWT verify
  (`AUTH_ENABLED=false` locally); `app/config.py` = env settings; `app/smoke.py` = Bedrock check.
- A **Bedrock Guardrail** is attached to every invocation when `BEDROCK_GUARDRAIL_ID` /
  `BEDROCK_GUARDRAIL_VERSION` are set (the `guardrail` TF module sets them on Lambda; empty locally
  → no guardrail). It scopes to AWS topics, runs content/prompt-attack filters, and redacts PII.

## Commands
- `make install` · `make smoke` · `make dev` · `make test` · `make lint` · `make fmt`
- `make tf-init|tf-plan|tf-apply|tf-destroy` (infra)
- Always load env first: handled by the Makefile (`set -a; source .env`).
- CI: `.github/workflows/ci.yml` runs ruff + pytest + `terraform fmt/validate` on every PR (no AWS
  creds). `deploy.yml` is a manual OIDC deploy (build/push image + `terraform apply`); if the shared
  account blocks the OIDC provider, deploy locally with `make tf-apply` instead.
- ⚠️ zsh applies `:l`/`:latest` as a history modifier — always write `${REPO}:latest` (braces), not
  `$REPO:latest`, in image tags, or the tag silently mangles.

## Conventions
- Keep the dual local/Lambda code path single (FastAPI app); don't fork a separate Lambda handler.
- Add cost/latency guards to any new agent path (`AGENT_MAX_TOKENS`, tool-iteration cap).
- Docker: PATH includes the Docker.app creds-helper (set in the Makefile) for builds/ECR pushes.
