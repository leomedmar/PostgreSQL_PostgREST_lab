# ================================================================
#  Makefile  --  PostgREST Multi-Tenant Lab
# ================================================================

.PHONY: up down logs status generate-tokens test-a test-b test-isolation test-auth-edge test-input-validation test-resilience test-cross-tenant-writes test-query-hardening test-api-surface test-integrity-consistency test-rebuild-baseline test-security-all test-integrity-all test-all psql clean demo-walkthrough demo-panes demo-dashboard

GREEN  = \033[0;32m
YELLOW = \033[0;33m
NC     = \033[0m

up:
	@echo "$(GREEN)▶ Starting containers...$(NC)"
	docker compose up -d
	@echo "$(GREEN)✅ Stack is up. PostgREST available at http://localhost:3000$(NC)"

down:
	@echo "$(YELLOW)▶ Stopping containers...$(NC)"
	docker compose down -v

logs:
	docker compose logs -f

status:
	docker compose ps

generate-tokens:
	@echo "$(GREEN)▶ Generating JWT tokens...$(NC)"
	@python3 -c "import jwt" 2>/dev/null || pip install -q PyJWT
	python3 tests/generate_tokens.py

test-a:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/01_test_tenant_a.sh; \
	  TOKEN_A=$$TOKEN_A bash tests/01_test_tenant_a.sh

test-b:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/02_test_tenant_b.sh; \
	  TOKEN_B=$$TOKEN_B bash tests/02_test_tenant_b.sh

test-isolation:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/03_test_cross_tenant.sh; \
	  TOKEN_A=$$TOKEN_A TOKEN_B=$$TOKEN_B bash tests/03_test_cross_tenant.sh

test-auth-edge:
	@chmod +x tests/04_test_auth_edge_cases.sh; \
	  if [ -z "$${JWT_SECRET:-}" ] && [ ! -f .env ]; then \
	    echo "ERROR: JWT_SECRET is not set and .env does not exist"; exit 1; \
	  fi; \
	  JWT_SECRET=$${JWT_SECRET:-$$(grep '^JWT_SECRET=' .env | cut -d '=' -f2-)} bash tests/04_test_auth_edge_cases.sh

test-input-validation:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/05_test_input_validation.sh; \
	  TOKEN_A=$$TOKEN_A bash tests/05_test_input_validation.sh

test-resilience:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/06_test_resilience.sh; \
	  TOKEN_A=$$TOKEN_A bash tests/06_test_resilience.sh

test-cross-tenant-writes:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/07_test_cross_tenant_writes.sh; \
	  TOKEN_A=$$TOKEN_A TOKEN_B=$$TOKEN_B bash tests/07_test_cross_tenant_writes.sh

test-query-hardening:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/08_test_query_bypass_hardening.sh; \
	  TOKEN_A=$$TOKEN_A TOKEN_B=$$TOKEN_B bash tests/08_test_query_bypass_hardening.sh

test-api-surface:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/09_test_api_surface_security.sh; \
	  TOKEN_A=$$TOKEN_A bash tests/09_test_api_surface_security.sh

test-integrity-consistency:
	@eval $$(python3 tests/generate_tokens.py 2>/dev/null | grep 'export TOKEN_'); \
	  chmod +x tests/10_test_data_integrity_consistency.sh; \
	  TOKEN_A=$$TOKEN_A bash tests/10_test_data_integrity_consistency.sh

test-rebuild-baseline:
	@chmod +x tests/11_test_rebuild_baseline.sh; \
	  bash tests/11_test_rebuild_baseline.sh

test-security-all: test-isolation test-auth-edge test-cross-tenant-writes test-query-hardening test-api-surface
	@echo "$(GREEN)✅ Security-focused suite complete.$(NC)"

test-integrity-all: test-input-validation test-resilience test-integrity-consistency
	@echo "$(GREEN)✅ Data integrity suite complete.$(NC)"

test-all: test-a test-b test-security-all test-integrity-all
	@echo "$(GREEN)✅ Full test suite complete.$(NC)"

psql:
	docker compose exec postgres psql -U postgres -d saas_lab

clean: down
	@echo "$(YELLOW)▶ Removing volumes...$(NC)"
	docker compose down -v
	docker compose stop
	@echo "$(GREEN)✅ Environment reset.$(NC)"

demo-walkthrough:
	@echo "$(GREEN)▶ Running visual walkthrough demo...$(NC)"
	bash demo/03_walkthrough.sh

demo-panes:
	@echo "$(GREEN)▶ Launching tmux demo panes...$(NC)"
	bash demo/start_demo_panes.sh

demo-dashboard:
	@echo "$(GREEN)▶ Starting dashboard container on http://127.0.0.1:8090$(NC)"
	docker compose up -d dashboard
	@echo "$(GREEN)✅ Dashboard available at http://127.0.0.1:8090$(NC)"
