#!/usr/bin/env bash
# ================================================================
#  05_test_input_validation.sh  --  Data validation and constraints
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
TOKEN_A="${TOKEN_A:?TOKEN_A is not set.}"

PASS=0
FAIL=0

check_rejected() {
  local description="$1"
  local code="$2"

  echo
  echo "> $description"
  echo "  HTTP: $code"

  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "  PASS -- invalid payload rejected"
    PASS=$((PASS + 1))
  else
    echo "  FAIL -- invalid payload accepted"
    FAIL=$((FAIL + 1))
  fi
}

echo "================================================================"
echo " INPUT VALIDATION TESTS"
echo "================================================================"

# 1) products.price cannot be negative
CODE="$(curl -s -o /tmp/validation_negative_price.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"name":"Invalid Negative Price","price":-1.00,"stock":10}' \
  "$BASE_URL/products")"
check_rejected "Reject product with negative price" "$CODE"

# 2) orders.amount must be greater than zero
CODE="$(curl -s -o /tmp/validation_zero_amount.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"customer_name":"Invalid Amount","product_id":1,"amount":0,"status":"pending"}' \
  "$BASE_URL/orders")"
check_rejected "Reject order with zero amount" "$CODE"

# 3) status check constraint
CODE="$(curl -s -o /tmp/validation_bad_status.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"customer_name":"Invalid Status","product_id":1,"amount":10.00,"status":"unknown"}' \
  "$BASE_URL/orders")"
check_rejected "Reject order with unsupported status" "$CODE"

# 4) foreign key integrity on product_id
CODE="$(curl -s -o /tmp/validation_fk.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"customer_name":"Invalid FK","product_id":99999,"amount":10.00,"status":"pending"}' \
  "$BASE_URL/orders")"
check_rejected "Reject order with unknown product_id" "$CODE"

# 5) malformed JSON payload
CODE="$(curl -s -o /tmp/validation_malformed_json.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"name":"Broken JSON"' \
  "$BASE_URL/products")"
check_rejected "Reject malformed JSON body" "$CODE"

# 6) missing required field (name)
CODE="$(curl -s -o /tmp/validation_missing_required.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Content-Profile: tenant_a" \
  -H "Content-Type: application/json" \
  -d '{"price":42.00,"stock":1}' \
  "$BASE_URL/products")"
check_rejected "Reject product missing required name" "$CODE"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
