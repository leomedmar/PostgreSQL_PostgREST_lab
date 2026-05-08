#!/usr/bin/env bash
# ================================================================
#  11_test_rebuild_baseline.sh  --  Rebuild and seed baseline check
# ================================================================

set -euo pipefail

PASS=0
FAIL=0

record_pass() {
  local description="$1"
  echo "PASS -- $description"
  PASS=$((PASS + 1))
}

record_fail() {
  local description="$1"
  echo "FAIL -- $description"
  FAIL=$((FAIL + 1))
}

assert_count() {
  local table_name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" == "$expected" ]]; then
    record_pass "$table_name has expected seed count ($expected)"
  else
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
    record_fail "$table_name seed count mismatch"
  fi
}

count_from_api() {
  local token="$1"
  local profile="$2"
  local endpoint="$3"

  local tmp_file
  tmp_file="$(mktemp)"

  local code
  code="$(curl -s -o "$tmp_file" -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept-Profile: $profile" \
    "${BASE_URL:-http://localhost:3000}/$endpoint")"

  if [[ "$code" != "200" ]]; then
    echo "ERROR_HTTP_$code"
    rm -f "$tmp_file"
    return
  fi

  python3 - "$tmp_file" <<'PY'
import json
import pathlib
import sys

rows = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(len(rows))
PY

  rm -f "$tmp_file"
}

echo "================================================================"
echo " REBUILD BASELINE TEST"
echo "================================================================"

echo
echo "> Rebuilding environment from scratch (make clean && make up)"
make clean >/dev/null
make up >/dev/null
record_pass "Environment rebuild completed"

echo
echo "> Waiting for API readiness..."
BASE_URL="${BASE_URL:-http://localhost:3000}"
for i in $(seq 1 30); do
  if curl -sf "$BASE_URL/" > /dev/null 2>&1; then
    record_pass "API is ready"
    break
  fi
  [[ "$i" -eq 30 ]] && { record_fail "API did not become ready within 30s"; exit 1; }
  sleep 1
done

echo
echo "> Generating tokens"
eval "$(python3 tests/generate_tokens.py | grep 'export TOKEN_')"

if [[ -z "${TOKEN_A:-}" || -z "${TOKEN_B:-}" ]]; then
  record_fail "Token generation failed after rebuild"
else
  record_pass "Token generation succeeded after rebuild"
fi

echo
echo "> Validating seed baseline counts"
A_PRODUCTS="$(count_from_api "$TOKEN_A" "tenant_a" "products")"
A_ORDERS="$(count_from_api "$TOKEN_A" "tenant_a" "orders")"
B_PRODUCTS="$(count_from_api "$TOKEN_B" "tenant_b" "products")"
B_ORDERS="$(count_from_api "$TOKEN_B" "tenant_b" "orders")"

assert_count "tenant_a.products" "3" "$A_PRODUCTS"
assert_count "tenant_a.orders" "4" "$A_ORDERS"
assert_count "tenant_b.products" "3" "$B_PRODUCTS"
assert_count "tenant_b.orders" "4" "$B_ORDERS"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
