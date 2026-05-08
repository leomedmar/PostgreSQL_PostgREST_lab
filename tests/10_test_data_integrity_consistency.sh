#!/usr/bin/env bash
# ==================================================================
#  10_test_data_integrity_consistency.sh  --  Integrity consistency
# ==================================================================

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

products_count() {
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

rows = json.loads(pathlib.Path(sys.argv[1]).read_text())
print(len(rows))
PY
}

echo "================================================================"
echo " DATA INTEGRITY CONSISTENCY TESTS"
echo "================================================================"

BASELINE_COUNT="$(products_count /tmp/integrity_before.json)"
if [[ "$BASELINE_COUNT" == ERROR_HTTP_* ]]; then
  record_fail "Could not read baseline product count ($BASELINE_COUNT)"
else
  echo "Baseline products: $BASELINE_COUNT"
  record_pass "Baseline product query succeeded"
fi

# 1) Invalid insert must fail
INVALID_CODE="$(curl -s -o /tmp/integrity_invalid_insert.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"name":"Invalid Integrity Insert","price":-123.45,"stock":1}' \
  "$BASE_URL/products")"

if [[ "$INVALID_CODE" != "200" && "$INVALID_CODE" != "201" ]]; then
  record_pass "Invalid write was rejected"
else
  record_fail "Invalid write was unexpectedly accepted"
fi

AFTER_INVALID_COUNT="$(products_count /tmp/integrity_after_invalid.json)"
if [[ "$AFTER_INVALID_COUNT" == "$BASELINE_COUNT" ]]; then
  record_pass "No extra rows persisted after failed insert"
else
  echo "Baseline: $BASELINE_COUNT"
  echo "After invalid: $AFTER_INVALID_COUNT"
  record_fail "Row count changed after failed insert"
fi

# 2) Valid insert then delete should preserve final count
INSERT_RESPONSE_FILE="/tmp/integrity_valid_insert.json"
VALID_INSERT_CODE="$(curl -s -o "$INSERT_RESPONSE_FILE" -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"name":"Integrity Temp Row","price":11.11,"stock":2}' \
  "$BASE_URL/products")"

if [[ "$VALID_INSERT_CODE" == "200" || "$VALID_INSERT_CODE" == "201" ]]; then
  record_pass "Valid insert succeeded"
else
  record_fail "Valid insert failed (HTTP $VALID_INSERT_CODE)"
fi

INSERTED_ID="$(python3 - "$INSERT_RESPONSE_FILE" <<'PY'
import json
import pathlib
import sys

raw = pathlib.Path(sys.argv[1]).read_text().strip()
if not raw:
    print("")
    raise SystemExit(0)

parsed = json.loads(raw)
if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict):
    print(parsed[0].get("id", ""))
else:
    print("")
PY
)"

if [[ -n "$INSERTED_ID" ]]; then
  DELETE_CODE="$(curl -s -o /tmp/integrity_delete.json -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: Bearer $TOKEN_A" \
    -H "Content-Profile: tenant_a" \
    "$BASE_URL/products?id=eq.$INSERTED_ID")"

  if [[ "$DELETE_CODE" == "200" || "$DELETE_CODE" == "204" ]]; then
    record_pass "Cleanup delete succeeded"
  else
    record_fail "Cleanup delete failed (HTTP $DELETE_CODE)"
  fi
else
  record_fail "Could not parse inserted product id for cleanup"
fi

FINAL_COUNT="$(products_count /tmp/integrity_final.json)"
if [[ "$FINAL_COUNT" == "$BASELINE_COUNT" ]]; then
  record_pass "Final row count matches baseline"
else
  echo "Baseline: $BASELINE_COUNT"
  echo "Final: $FINAL_COUNT"
  record_fail "Final row count does not match baseline"
fi

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
