#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
DEMO_DELAY_SECONDS="${DEMO_DELAY_SECONDS:-1}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}Missing required command: $cmd${NC}"
    exit 1
  fi
}

print_banner() {
  echo
  echo "=============================================================="
  echo " PostgREST Multi-Tenant Demo Walkthrough"
  echo "=============================================================="
  echo "BASE_URL: $BASE_URL"
  echo
}

wait_for_api() {
  local attempts=30
  local i

  for i in $(seq 1 "$attempts"); do
    if curl -sS "$BASE_URL/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo -e "${RED}PostgREST is not reachable at $BASE_URL${NC}"
  exit 1
}

load_tokens() {
  eval "$(python3 tests/generate_tokens.py | grep 'export TOKEN_')"

  if [[ -z "${TOKEN_A:-}" || -z "${TOKEN_B:-}" ]]; then
    echo -e "${RED}Could not generate TOKEN_A/TOKEN_B${NC}"
    exit 1
  fi
}

pretty_print_json() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
raw = path.read_text().strip()
if not raw:
    print("<empty body>")
    raise SystemExit(0)

try:
    parsed = json.loads(raw)
except Exception:
    print(raw[:600])
    raise SystemExit(0)

if isinstance(parsed, list):
    print(f"JSON array with {len(parsed)} item(s)")
    preview = parsed[:2]
    print(json.dumps(preview, indent=2))
elif isinstance(parsed, dict):
    print("JSON object")
    print(json.dumps(parsed, indent=2))
else:
    print(str(parsed))
PY
}

record_result() {
  local ok="$1"
  local message="$2"

  if [[ "$ok" == "yes" ]]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC} - $message"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC} - $message"
  fi
}

run_scenario() {
  local title="$1"
  local token="$2"
  local profile="$3"
  local expect_deny="$4"

  local tmp_body
  tmp_body="$(mktemp)"

  echo
  echo -e "${BLUE}>>> $title${NC}"
  echo "Request: GET /products | Accept-Profile: $profile"

  local code
  if [[ -n "$token" ]]; then
    code="$(curl -sS -o "$tmp_body" -w "%{http_code}" -H "Authorization: Bearer $token" -H "Accept-Profile: $profile" "$BASE_URL/products")"
  else
    code="$(curl -sS -o "$tmp_body" -w "%{http_code}" -H "Accept-Profile: $profile" "$BASE_URL/products")"
  fi

  echo "HTTP status: $code"
  pretty_print_json "$tmp_body"

  if [[ "$expect_deny" == "yes" ]]; then
    if [[ "$code" != "200" && "$code" != "201" ]]; then
      record_result "yes" "Access denied as expected"
    else
      if python3 - "$tmp_body" <<'PY'
import json
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_text().strip() or "[]"
try:
    parsed = json.loads(raw)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if isinstance(parsed, list) and len(parsed) == 0 else 1)
PY
      then
        record_result "yes" "HTTP 200 with empty array (RLS safeguard)"
      else
        record_result "no" "Data exposed to an unauthorised tenant"
      fi
    fi
  else
    if [[ "$code" == "200" || "$code" == "201" ]]; then
      record_result "yes" "Access granted as expected"
    else
      record_result "no" "Legitimate access was denied"
    fi
  fi

  rm -f "$tmp_body"
  sleep "$DEMO_DELAY_SECONDS"
}

main() {
  require_command docker
  require_command curl
  require_command python3

  print_banner

  echo -e "${YELLOW}Ensuring containers are running...${NC}"
  if ! curl -sf "$BASE_URL/" >/dev/null 2>&1; then
    docker compose up -d
  fi

  echo -e "${YELLOW}Waiting for API readiness...${NC}"
  wait_for_api

  echo -e "${YELLOW}Generating demo tokens...${NC}"
  load_tokens

  run_scenario "Scenario 1 - TOKEN_A tries tenant_b (expect deny)" "$TOKEN_A" "tenant_b" "yes"
  run_scenario "Scenario 2 - TOKEN_B tries tenant_a (expect deny)" "$TOKEN_B" "tenant_a" "yes"
  run_scenario "Scenario 3 - anon tries tenant_a (expect deny)" "" "tenant_a" "yes"
  run_scenario "Scenario 4 - TOKEN_A uses tenant_a (expect allow)" "$TOKEN_A" "tenant_a" "no"
  run_scenario "Scenario 5 - TOKEN_B uses tenant_b (expect allow)" "$TOKEN_B" "tenant_b" "no"

  echo
  echo "=============================================================="
  echo " Demo Summary"
  echo "=============================================================="
  echo -e "PASSED: ${GREEN}$PASS${NC}"
  echo -e "FAILED: ${RED}$FAIL${NC}"

  if [[ "$FAIL" -eq 0 ]]; then
    echo -e "${GREEN}Demo finished successfully.${NC}"
  else
    echo -e "${RED}Demo finished with failures.${NC}"
    exit 1
  fi
}

main "$@"
