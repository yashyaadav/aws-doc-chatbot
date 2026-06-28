# Agentic AWS Documentation Chatbot

A serverless chatbot that answers AWS questions in natural language by **reasoning over the
live AWS documentation**. A Claude (Opus 4.8) agent on Amazon Bedrock calls the official
[awslabs AWS Documentation MCP server](https://github.com/awslabs/mcp) as a tool — it searches
and reads real AWS docs at query time and answers **with citations**, rather than relying on the
model's training memory. Everything is Infrastructure-as-Code (Terraform).

```
Browser ─▶ CloudFront ─▶ API Gateway (HTTP) ─▶ Lambda (container)
                                                    │  Strands agent loop
                                                    ├─ Claude Opus 4.8 on Bedrock
                                                    └─ AWS-Docs MCP server (stdio, in-image) ─▶ docs.aws.amazon.com
                                                    │
                                            DynamoDB (history)   Cognito (auth, JWT verified in-handler)
```

> **Live:** https://d47xudcf1qjnj.cloudfront.net — sign in with the demo user (`demo@example.com`;
> password shared separately). Deployed to AWS account 315311531132 / us-east-1.

> **Ingress note:** the design targets a streaming **Lambda Function URL** (no API Gateway 29s cap).
> The shared exam account blocks Function URL invocation via an org guardrail, so the deployed path
> uses **API Gateway** (buffered, 30s cap) instead. The Function URL design is preferred in an
> unrestricted account; both are in the Terraform (the `apigw` module is the active ingress).

See [docs/architecture.md](docs/architecture.md) for the full design, request flow, and
alternatives considered.

## Why this design
- **Live docs, not stale RAG** — the AWS-Docs MCP server fetches current documentation per query;
  no ingestion pipeline to build or keep fresh.
- **Genuinely agentic** — the model decides when to `search_documentation` / `read_documentation`
  and iterates; tool calls are visible in logs (proof it isn't answering from memory).
- **Production-grade serverless** — CloudFront + API Gateway + container Lambda, Cognito auth,
  DynamoDB session state, least-privilege IAM, a Bedrock Guardrail (AWS-topic scoping + content
  filters + PII redaction), observability + budget alarm — all in Terraform, with GitHub Actions CI.

## Quickstart (local)
```bash
cp .env.example .env          # set AWS_PROFILE + region (no secrets stored)
make install                  # venv (py3.12) + deps
make smoke                    # Bedrock converse check (confirms model access)
make dev                      # FastAPI chat server on :8080
# then:
curl -N localhost:8080/api/chat -H 'content-type: application/json' \
  -d '{"session_id":"s1","message":"How do I enable S3 versioning with the AWS CLI?"}'
```

## Layout
```
backend/    FastAPI app (Strands agent + MCP client + Bedrock) — runs locally and on Lambda
infra/      Terraform (modules + envs/dev)
frontend/   static chat UI (CloudFront/S3)
docs/       architecture + rationale
```

## Configuration
All via env (see `.env.example`): `BEDROCK_MODEL_ID` (default the Opus 4.8 global inference
profile), `AWS_REGION`, `AGENT_MAX_TOKENS`/`AGENT_MAX_TOOL_ITERATIONS` (cost/latency guards),
`CONVERSATIONS_TABLE` (DynamoDB; empty = in-memory for local), `AUTH_ENABLED` + Cognito ids.

## Cost
On-demand only: Bedrock per-token (Opus 4.8), Lambda per-invocation, DynamoDB on-demand,
CloudFront/S3 negligible at rest. A Budgets alarm is provisioned. `make tf-destroy` tears it down.

## Status
- [x] **M0** — account verified (315311531132 / us-east-1), permissions probed, Bedrock access confirmed
- [x] **M1** — agent core: Bedrock + AWS-Docs MCP, streaming, multi-turn memory, tests (local-first)
- [x] **M2** — deployed: ECR/Lambda, API Gateway, DynamoDB, Cognito, CloudFront, IAM, observability;
  end-to-end authenticated chat verified live (Function URL → API Gateway pivot due to org guardrail)
- [x] **M3** — polish: Bedrock Guardrail (AWS-topic scoping + content/PII filters) applied on every
  invocation and verified live; GitHub Actions CI (lint + test + `terraform validate`) + manual
  OIDC deploy workflow

> Runs in a **shared exam account** — every resource is namespaced `yy-awsdocs-*` and only
> self-created resources are touched. See [docs/architecture.md](docs/architecture.md).
