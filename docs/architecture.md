# Architecture

## Goal
Let a user ask AWS questions in natural language and get answers grounded in the **live** AWS
documentation, delivered as a production-grade serverless app provisioned with Terraform.

## Diagram
```
                    Browser (static chat UI + Cognito Hosted UI login)
                                │ HTTPS  (JWT: Authorization: Bearer)
                        CloudFront (TLS, single domain)
                       ┌────────┴───────────────────────┐
              /  (static)                         /api/* (chat)
          S3 static site (OAC)        API Gateway (HTTP) ─▶ Lambda proxy
                                       Lambda (container image)  ── IAM exec role
                                       ┌──────────────────────────────────────┐
                                       │  verify Cognito JWT (in-handler)      │
                                       │  Strands agent loop                   │
                                       │   ├─ Claude Opus 4.8 on Bedrock       │ ─▶ bedrock:InvokeModel (global profile)
                                       │   └─ AWS-Docs MCP server              │ ─▶ docs.aws.amazon.com
                                       │        (stdio subprocess, in-image)   │    (Lambda not in a VPC → egress)
                                       └───────────────┬──────────────────────┘
                                                       │ read/write turn history
                                            DynamoDB  yy-awsdocs-conversations
                                                       │
                              CloudWatch Logs / Metrics / X-Ray + Bedrock invocation logging
                              + AWS Budgets alarm  + Bedrock Guardrail (applied on every invocation)
```

## Request flow
1. Browser logs in via the Cognito Hosted UI, gets a JWT, and POSTs `/api/chat`
   (`{session_id, message}`) with `Authorization: Bearer <jwt>` through CloudFront.
2. The Lambda (FastAPI app behind the AWS Lambda Web Adapter) verifies the JWT, loads prior turns
   from DynamoDB, and builds a Strands agent seeded with that history.
3. The agent runs the reason→tool→observe loop on Opus 4.8: it calls the AWS-Docs MCP tools
   (`search_documentation`, `read_documentation`, `read_sections`, `recommend`) which fetch live
   docs, then composes an answer with citation URLs.
4. Tokens stream back to the browser as Server-Sent Events; the completed turn is persisted to
   DynamoDB.

## Key decisions
- **Live docs via MCP, not RAG.** No crawl/embed/index pipeline; answers reflect current docs and
  the tool calls are auditable in logs.
- **Strands Agents** runs the agentic loop and adapts MCP tools to Bedrock — least boilerplate,
  AWS-native. Note: Amazon Bedrock does not offer Anthropic Managed Agents / server-side tools, so
  the loop is client-side, hosted in our Lambda (this is **not** "Bedrock Agents").
- **Claude on Bedrock via a global inference profile.** The deployed path defaults to **Sonnet 4.6**
  (`global.anthropic.claude-sonnet-4-6`) because it is materially faster per step than Opus, which
  matters under the API Gateway 30s cap; **Opus 4.8**
  (`global.anthropic.claude-opus-4-8`) is a one-variable swap (`bedrock_model_id`) for max quality,
  and the Lambda IAM already allows both. Sampling params (`temperature`/`top_p`) are not accepted on
  this model family — confirmed via the smoke test.
- **Latency guards for the 30s buffered cap.** An agentic turn does several live doc fetches plus
  generation, which can exceed API Gateway's limit. Mitigations: Sonnet 4.6, a **hard cap of 3 tool
  calls per turn** (a Strands `BeforeToolCallEvent` hook that cancels the 4th with an "answer now"
  message — graceful, not truncation), `AGENT_MAX_TOKENS=2000`, and 2048 MB Lambda memory to keep
  cold-start init under the 10s window. Broad questions now complete (~24s) instead of timing out.
  The 30s is a **hard limit** — HTTP API integration timeouts can't be raised (a REST API could be
  quota-increased, but the streaming Function URL is the better fix). If a turn *still* exceeds 30s
  (cold start + a multi-step question), the Lambda finishes and **persists the turn**, and the UI
  **auto-recovers it from `/api/history`** rather than failing. The residual cost is a slow first-hit
  cold start (~15-18s); **provisioned concurrency is deliberately omitted** to avoid standing demo
  cost — it, or the streaming Function URL (blocked here), would remove it.
- **Ingress: CloudFront → API Gateway (HTTP) → Lambda.** The *intended* design was a streaming
  **Lambda Function URL** behind CloudFront (avoids API Gateway's 29s cap, which an Opus agentic
  turn can exceed). **This shared exam account blocks Function URL invocation via an org guardrail**
  (both public `NONE` auth and CloudFront-OAC-signed `AWS_IAM` return 403), so the deployed ingress
  is API Gateway HTTP API → Lambda proxy (buffered, 30s cap), with `AGENT_MAX_TOKENS` lowered to fit.
  In an unrestricted account, flip the `lambda` module back to a `RESPONSE_STREAM` Function URL +
  CloudFront OAC. The agent still streams SSE; API Gateway buffers it and the UI renders the result.
- **MCP server packaged in the image** (pip-installed at build, launched as `python -m
  awslabs.aws_documentation_mcp_server.server` — PATH-independent), spawned once per warm container
  and reused. Lambda stays out of a VPC so it can reach `docs.aws.amazon.com`.
- **DynamoDB for conversation state** (Lambda is stateless): one item per session, full message
  list as JSON, with a TTL. In-memory fallback for local dev.
- **Cost/latency guards:** `AGENT_MAX_TOKENS`, a tool-iteration cap, Bedrock prompt caching on the
  stable system prompt, and an AWS Budgets alarm.
- **Bedrock Guardrail (defense in depth).** A guardrail is attached to every Bedrock invocation
  (Strands `BedrockModel(guardrail_id, guardrail_version)`): a denied **topic policy** keeps the bot
  out of legal/medical/financial advice, **content filters** (hate/sexual/violence/misconduct +
  `PROMPT_ATTACK` to resist prompt-injection of the system prompt), and a **PII policy** that blocks
  card numbers / SSNs / AWS secret keys and anonymizes emails before they reach the model or logs.
  Off-topic or unsafe input gets the scoped refusal message; the system prompt already steers toward
  AWS, and the guardrail enforces it server-side. The Lambda role grants only `bedrock:ApplyGuardrail`
  on this one guardrail ARN.

## Alternatives considered
- **Anthropic SDK (`AnthropicBedrock`) + a hand-written MCP tool-use loop** instead of Strands:
  more direct control over streaming/caching/citations, but more boilerplate (list MCP tools →
  convert to Anthropic tool schemas → dispatch `tool_use` blocks → loop). Strands was chosen for
  speed of delivery and AWS-native fit. No dual code path is maintained.
- **Bedrock Knowledge Base (RAG) over crawled docs:** rejected — adds an ingestion pipeline, vector
  store cost, and staleness, for a docs corpus the MCP server already serves live.
- **API Gateway (HTTP/WebSocket):** HTTP API's 29s cap is too tight for Opus agentic turns;
  WebSocket adds protocol complexity. The streaming Function URL is simpler and sufficient.

## Shared-account guardrails
This runs in a shared AllCloud exam account (315311531132) with other tenants' resources. Every
resource is namespaced `yy-awsdocs-*`, Terraform uses its own state bucket
(`yy-awsdocs-tfstate-315311531132`), and only self-created resources are read or modified.
