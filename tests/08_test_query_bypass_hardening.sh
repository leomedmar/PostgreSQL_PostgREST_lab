#!/usr/bin/env bash
# =======================================================================
#  08_test_query_bypass_hardening.sh  --  Complex query bypass attempts
# =======================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"
TOKEN_B="${TOKEN_B:?TOKEN_B is not set.}"

PASS=0
FAIL=0

check_denied_or_empty() {
  local description="$1"
  local code="$2"
  local body_file="$3"

  echo
  echo "> $description"
  echo "  HTTP: $code"

  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "  PASS -- query denied as expected"
    PASS=$((PASS + 1))
    return
  fi

  if python3 - "$body_file" <<'PY'
import json
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_text().strip() or "[]"
parsed = json.loads(body)
raise SystemExit(0 if isinstance(parsed, list) and len(parsed) == 0 else 1)
PY
  then
    echo "  PASS -- HTTP 200 but empty array (no cross-tenant exposure)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL -- response returned data for forbidden scenario"
    FAIL=$((FAIL + 1))
  fi
}

run_case() {
  local description="$1"
  local token="$2"
  local profile="$3"
  local endpoint="$4"
  local body_file="$5"

  local code
  code="$(curl -s -o "$body_file" -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept-Profile: $profile" \
    "$BASE_URL$endpoint")"

  check_denied_or_empty "$description" "$code" "$body_file"
}

echo "================================================================"
echo " QUERY BYPASS HARDENING TESTS"
echo "================================================================"

run_case "TOKEN_A tries tenant_b with embedding select" "$TOKEN_A" "tenant_b" "/orders?select=*,products(name,price)" "/tmp/bypass_1.json"
run_case "TOKEN_A tries tenant_b with OR filter" "$TOKEN_A" "tenant_b" "/orders?or=(status.eq.pending,status.eq.completed)" "/tmp/bypass_2.json"
run_case "TOKEN_A tries tenant_b with ordering and pagination" "$TOKEN_A" "tenant_b" "/products?order=created_at.desc&limit=2&offset=0" "/tmp/bypass_3.json"
run_case "TOKEN_B tries tenant_a with wildcard-like select" "$TOKEN_B" "tenant_a" "/orders?select=id,customer_name,amount,status" "/tmp/bypass_4.json"
run_case "TOKEN_B tries tenant_a with range and filters" "$TOKEN_B" "tenant_a" "/orders?amount=gte.1&amount=lte.1000" "/tmp/bypass_5.json"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
