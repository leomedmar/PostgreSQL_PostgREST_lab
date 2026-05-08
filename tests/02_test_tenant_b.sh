#!/usr/bin/env bash
# ================================================================
#  02_test_tenant_b.sh  --  Tenant B endpoint tests
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN="${TOKEN_B:?TOKEN_B is not set. Run generate_tokens.py first.}"

sep() { echo; echo "────────────────────────────────────────"; echo "$1"; echo "────────────────────────────────────────"; }

sep "1. GET /products  (Tenant B)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_b" \
  -H "Accept: application/json" \
  "$BASE_URL/products" | python3 -m json.tool

sep "2. GET /orders  (Tenant B)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_b" \
  -H "Accept: application/json" \
  "$BASE_URL/orders" | python3 -m json.tool

sep "3. GET /orders?status=eq.processing  (Tenant B)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_b" \
  -H "Accept: application/json" \
  "$BASE_URL/orders?status=eq.processing" | python3 -m json.tool

sep "4. GET /orders?select=*,products(name,price)  (resource embedding)"
curl -sf \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Profile: tenant_b" \
  -H "Accept: application/json" \
  "$BASE_URL/orders?select=*,products(name,price)" | python3 -m json.tool

echo
echo "✅ All Tenant B tests passed."
