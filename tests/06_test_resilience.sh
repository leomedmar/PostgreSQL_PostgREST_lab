#!/usr/bin/env bash
# ================================================================
#  06_test_resilience.sh  --  Basic service resilience checks
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"

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

fetch_products_count() {
  local output_file="$1"

  local code
  code="$(curl -s -o "$output_file" -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Accept-Profile: tenant_a" \
    "$BASE_URL/products")"

  if [[ "$code" != "200" ]]; then
    echo "ERROR_HTTP_$code"
    return
  fi

  python3 - "$output_file" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
rows = json.loads(path.read_text())
print(len(rows))
PY
}

wait_for_http_200() {
  local max_attempts="$1"
  local delay_seconds="$2"

  local attempt
  for attempt in $(seq 1 "$max_attempts"); do
    local code
    code="$(curl -s -o /tmp/resilience_probe.json -w "%{http_code}" \
      -H "Authorization: Bearer $TOKEN_A" \
      -H "Accept-Profile: tenant_a" \
      "$BASE_URL/products")"

    if [[ "$code" == "200" ]]; then
      return 0
    fi

    sleep "$delay_seconds"
  done

  return 1
}

echo "================================================================"
echo " RESILIENCE TESTS"
echo "================================================================"

echo
echo "> Baseline tenant_a product count"
BASELINE_COUNT="$(fetch_products_count /tmp/resilience_before.json)"
if [[ "$BASELINE_COUNT" == ERROR_HTTP_* ]]; then
  record_fail "Could not read baseline data ($BASELINE_COUNT)"
else
  echo "  Baseline products: $BASELINE_COUNT"
  record_pass "Baseline query succeeded"
fi

echo
echo "> Restart PostgREST and verify recovery"
docker compose restart postgrest >/dev/null
if wait_for_http_200 30 1; then
  record_pass "PostgREST recovered after restart"
else
  record_fail "PostgREST did not recover in time"
fi

echo
echo "> Validate data availability after restart"
AFTER_RESTART_COUNT="$(fetch_products_count /tmp/resilience_after_restart.json)"
if [[ "$AFTER_RESTART_COUNT" == ERROR_HTTP_* ]]; then
  record_fail "Could not query data after restart ($AFTER_RESTART_COUNT)"
elif [[ "$AFTER_RESTART_COUNT" == "$BASELINE_COUNT" ]]; then
  echo "  Products after restart: $AFTER_RESTART_COUNT"
  record_pass "Data remained consistent after restart"
else
  echo "  Baseline: $BASELINE_COUNT"
  echo "  After restart: $AFTER_RESTART_COUNT"
  record_fail "Data count changed unexpectedly after restart"
fi

echo
echo "> Confirm cross-tenant denial still works after restart"
CODE="$(curl -s -o /tmp/resilience_cross_tenant.json -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: tenant_b" \
  "$BASE_URL/products")"
if [[ "$CODE" != "200" && "$CODE" != "201" ]]; then
  record_pass "Cross-tenant denial is still enforced"
else
  record_fail "Cross-tenant request was unexpectedly allowed"
fi

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
