# Agentic AWS Documentation Chatbot — developer workflow
# Local AWS creds come from the `assignment` profile via .env (set -a; source .env).

SHELL := /bin/bash
# Per environment note: Docker creds-helper lives here on this machine.
export PATH := /Applications/Docker.app/Contents/Resources/bin:$(PATH)

BACKEND := backend
PY := $(BACKEND)/.venv/bin/python

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_.-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Create backend venv (py3.12) and install deps
	cd $(BACKEND) && uv venv --python 3.12 && uv pip install -e ".[dev]"

.PHONY: smoke
smoke: ## Bedrock converse smoke test (confirms model access + invocation id)
	set -a; source .env; set +a; $(PY) -m app.smoke

.PHONY: dev
dev: ## Run the FastAPI chat server locally (hot reload)
	set -a; source .env; set +a; cd $(BACKEND) && .venv/bin/uvicorn app.main:app --reload --port $${PORT:-8080}

.PHONY: test
test: ## Run unit tests (mocked Bedrock + MCP + JWT)
	cd $(BACKEND) && .venv/bin/pytest -q

.PHONY: lint
lint: ## Lint with ruff
	cd $(BACKEND) && .venv/bin/ruff check app tests

.PHONY: fmt
fmt: ## Format with ruff
	cd $(BACKEND) && .venv/bin/ruff format app tests

# --- Infra (filled in during M2) ---
.PHONY: tf-init tf-plan tf-apply tf-destroy
tf-init: ## terraform init (dev)
	set -a; source .env; set +a; cd infra/envs/dev && terraform init
tf-plan: ## terraform plan (dev)
	set -a; source .env; set +a; cd infra/envs/dev && terraform plan -var-file=dev.tfvars
tf-apply: ## terraform apply (dev)
	set -a; source .env; set +a; cd infra/envs/dev && terraform apply -var-file=dev.tfvars
tf-destroy: ## terraform destroy (dev)
	set -a; source .env; set +a; cd infra/envs/dev && terraform destroy -var-file=dev.tfvars
