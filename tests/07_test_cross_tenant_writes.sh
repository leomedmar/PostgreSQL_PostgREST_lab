#!/usr/bin/env bash
# ================================================================
#  07_test_cross_tenant_writes.sh  --  Cross-tenant write denials
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"
TOKEN_B="${TOKEN_B:?TOKEN_B is not set.}"

PASS=0
FAIL=0

check_denied() {
  local description="$1"
  local code="$2"

  echo
  echo "> $description"
  echo "  HTTP: $code"

  if [[ "$code" != "200" && "$code" != "201" && "$code" != "204" ]]; then
    echo "  PASS -- write denied as expected"
    PASS=$((PASS + 1))
  else
    echo "  FAIL -- write unexpectedly allowed"
    FAIL=$((FAIL + 1))
  fi
}

echo "================================================================"
echo " CROSS-TENANT WRITE TESTS"
echo "================================================================"

# 1) TOKEN_A tries POST into tenant_b
CODE="$(curl -s -o /tmp/write_denied_1.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_b" \
  -H "Content-Type: application/json" \
  -d '{"name":"Illegal Insert","price":10.00,"stock":1}' \
  "$BASE_URL/products")"
check_denied "TOKEN_A POST on tenant_b" "$CODE"

# 2) TOKEN_B tries POST into tenant_a
CODE="$(curl -s -o /tmp/write_denied_2.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"name":"Illegal Insert","price":10.00,"stock":1}' \
  "$BASE_URL/products")"
check_denied "TOKEN_B POST on tenant_a" "$CODE"

# 3) TOKEN_A tries PATCH in tenant_b
CODE="$(curl -s -o /tmp/write_denied_3.json -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_b" \
  -H "Content-Type: application/json" \
  -d '{"price":999.99}' \
  "$BASE_URL/products?id=eq.1")"
check_denied "TOKEN_A PATCH on tenant_b" "$CODE"

# 4) TOKEN_B tries PATCH in tenant_a
CODE="$(curl -s -o /tmp/write_denied_4.json -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"price":999.99}' \
  "$BASE_URL/products?id=eq.1")"
check_denied "TOKEN_B PATCH on tenant_a" "$CODE"

# 5) TOKEN_A tries DELETE in tenant_b
CODE="$(curl -s -o /tmp/write_denied_5.json -w "%{http_code}" \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_b" \
  "$BASE_URL/products?id=eq.1")"
check_denied "TOKEN_A DELETE on tenant_b" "$CODE"

# 6) TOKEN_B tries DELETE in tenant_a
CODE="$(curl -s -o /tmp/write_denied_6.json -w "%{http_code}" \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Content-Profile: tenant_a" \
  "$BASE_URL/products?id=eq.1")"
check_denied "TOKEN_B DELETE on tenant_a" "$CODE"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
