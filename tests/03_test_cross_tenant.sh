#!/usr/bin/env bash
# ================================================================
#  03_test_cross_tenant.sh  --  Isolation and RLS validation
# ================================================================
#
#  Tests cross-tenant access attempts. All denial scenarios must
#  return a non-200 HTTP status code or an empty JSON array.
#  The script exits with code 1 if any assertion fails.
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"
TOKEN_B="${TOKEN_B:?TOKEN_B is not set.}"

PASS=0
FAIL=0

check() {
  local description="$1"
  local expect_deny="$2"   # "yes" if we expect the request to be denied
  local http_code="$3"
  local body="$4"

  echo
  echo "▶ $description"
  echo "  HTTP: $http_code"

  if [ "$expect_deny" = "yes" ]; then
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
      echo "  ✅ PASS -- access denied as expected (HTTP $http_code)"
      PASS=$((PASS+1))
    else
      # HTTP 200 is acceptable only if PostgREST returns an empty array (RLS blocked rows)
      if echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if len(d)==0 else 1)" 2>/dev/null; then
        echo "  ✅ PASS -- HTTP 200 but empty result (RLS blocked all rows)"
        PASS=$((PASS+1))
      else
        echo "  ❌ FAIL -- data exposed to wrong tenant!"
        echo "  Body: $body"
        FAIL=$((FAIL+1))
      fi
    fi
  else
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
      echo "  ✅ PASS -- access granted (HTTP $http_code)"
      PASS=$((PASS+1))
    else
      echo "  ❌ FAIL -- access unexpectedly denied (HTTP $http_code)"
      FAIL=$((FAIL+1))
    fi
  fi
}

echo "================================================================"
echo " CROSS-TENANT ISOLATION TESTS"
echo "================================================================"

# Scenario 1: TOKEN_A requests tenant_b schema
# role claim = tenant_a_role, but Accept-Profile = tenant_b
# tenant_a_role has no USAGE on schema tenant_b → should be denied
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: tenant_b" \
  "$BASE_URL/products" 2>/dev/null)
BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)
check "TOKEN_A accessing schema tenant_b (must be denied)" "yes" "$CODE" "$BODY"

# Scenario 2: TOKEN_B requests tenant_a schema
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Accept-Profile: tenant_a" \
  "$BASE_URL/products" 2>/dev/null)
BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)
check "TOKEN_B accessing schema tenant_a (must be denied)" "yes" "$CODE" "$BODY"

# Scenario 3: No token (anon role) accessing tenant_a
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Accept-Profile: tenant_a" \
  "$BASE_URL/products" 2>/dev/null)
BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)
check "No token (anon) accessing tenant_a (must be denied)" "yes" "$CODE" "$BODY"

# Scenario 4: TOKEN_A accessing its own schema (must succeed)
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: tenant_a" \
  "$BASE_URL/products" 2>/dev/null)
BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)
check "TOKEN_A accessing its own schema tenant_a (must succeed)" "no" "$CODE" "$BODY"

# Scenario 5: TOKEN_B accessing its own schema (must succeed)
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $TOKEN_B" \
  -H "Accept-Profile: tenant_b" \
  "$BASE_URL/products" 2>/dev/null)
BODY=$(echo "$RESPONSE" | head -n -1)
CODE=$(echo "$RESPONSE" | tail -n 1)
check "TOKEN_B accessing its own schema tenant_b (must succeed)" "no" "$CODE" "$BODY"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
