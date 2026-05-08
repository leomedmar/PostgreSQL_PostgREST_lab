#!/usr/bin/env bash
# ================================================================
#  09_test_api_surface_security.sh  --  API surface hardening checks
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"

PASS=0
FAIL=0

check_non_2xx() {
  local description="$1"
  local code="$2"

  echo
  echo "> $description"
  echo "  HTTP: $code"

  if [[ "$code" != "200" && "$code" != "201" && "$code" != "204" ]]; then
    echo "  PASS -- request correctly rejected"
    PASS=$((PASS + 1))
  else
    echo "  FAIL -- request unexpectedly accepted"
    FAIL=$((FAIL + 1))
  fi
}

echo "================================================================"
echo " API SURFACE SECURITY TESTS"
echo "================================================================"

# 1) Attempt to query using public schema profile
CODE="$(curl -s -o /tmp/surface_1.json -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: public" \
  "$BASE_URL/products")"
check_non_2xx "Reject profile outside configured tenant schemas (public)" "$CODE"

# 2) Attempt to query using pg_catalog schema profile
CODE="$(curl -s -o /tmp/surface_2.json -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: pg_catalog" \
  "$BASE_URL/products")"
check_non_2xx "Reject profile outside configured tenant schemas (pg_catalog)" "$CODE"

# 3) Attempt write with missing Content-Type for JSON body
CODE="$(curl -s -o /tmp/surface_3.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -d '{"name":"Missing Profile","price":1.00,"stock":1}' \
  "$BASE_URL/products")"
check_non_2xx "Reject write without JSON Content-Type" "$CODE"

# 4) Attempt write with forged Content-Profile tenant_b using token_a
CODE="$(curl -s -o /tmp/surface_4.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_b" \
  -H "Content-Type: application/json" \
  -d '{"name":"Forged Profile","price":1.00,"stock":1}' \
  "$BASE_URL/products")"
check_non_2xx "Reject forged Content-Profile for another tenant" "$CODE"

# 5) Unknown RPC endpoint should not expose internals
CODE="$(curl -s -o /tmp/surface_5.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$BASE_URL/rpc/internal_function")"
check_non_2xx "Unknown RPC endpoint is rejected" "$CODE"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
