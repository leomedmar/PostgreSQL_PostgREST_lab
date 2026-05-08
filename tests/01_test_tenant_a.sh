#!/usr/bin/env bash
# ================================================================
#  01_test_tenant_a.sh  --  Tenant A endpoint tests
# ================================================================
#
#  Pre-requisite: export TOKEN_A before running this script.
#    eval $(python3 tests/generate_tokens.py | grep 'export TOKEN_')
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN="${TOKEN_A:?TOKEN_A is not set. Run generate_tokens.py first.}"

sep() { echo; echo "────────────────────────────────────────"; echo "$1"; echo "────────────────────────────────────────"; }

sep "1. GET /products  (Tenant A)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_a" \
  -H "Accept: application/json" \
  "$BASE_URL/products" | python3 -m json.tool

sep "2. GET /orders  (Tenant A)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_a" \
  -H "Accept: application/json" \
  "$BASE_URL/orders" | python3 -m json.tool

sep "3. GET /orders?status=eq.completed  (Tenant A)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_a" \
  -H "Accept: application/json" \
  "$BASE_URL/orders?status=eq.completed" | python3 -m json.tool

sep "4. GET /orders?select=*,products(name,price)  (resource embedding)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_a" \
  -H "Accept: application/json" \
  "$BASE_URL/orders?select=*,products(name,price)" | python3 -m json.tool

sep "5. POST /products then DELETE  (insert and clean up)"
RESPONSE=$(curl -sf \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"name":"Trial Plan","price":0.00,"stock":0}' \
  "$BASE_URL/products")
echo "$RESPONSE" | python3 -m json.tool
INSERTED_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
curl -sf \
  -X DELETE \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Profile: tenant_a" \
  "$BASE_URL/products?id=eq.$INSERTED_ID" > /dev/null
echo "(Cleaned up: deleted product id=$INSERTED_ID)"

echo
echo "✅ All Tenant A tests passed."
