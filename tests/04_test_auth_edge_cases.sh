#!/usr/bin/env bash
# ================================================================
#  04_test_auth_edge_cases.sh  --  JWT/authentication edge cases
# ================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
JWT_SECRET="${JWT_SECRET:-lab-super-secret-jwt-key-32chars!!}"

PASS=0
FAIL=0

check_denied() {
  local description="$1"
  local code="$2"

  echo
  echo "> $description"
  echo "  HTTP: $code"

  if [[ "$code" != "200" && "$code" != "201" ]]; then
    echo "  PASS -- request denied as expected"
    PASS=$((PASS + 1))
  else
    echo "  FAIL -- request unexpectedly allowed"
    FAIL=$((FAIL + 1))
  fi
}

assert_token() {
  local name="$1" value="$2"
  [[ -n "$value" ]] || { echo "ERROR: failed to generate $name"; exit 1; }
}

make_token() {
  local role="$1"
  local tenant="$2"
  local expiration_shift="$3"

  python3 - "$role" "$tenant" "$expiration_shift" "$JWT_SECRET" <<'PY'
import datetime
import sys

import jwt

role = sys.argv[1]
tenant = sys.argv[2]
expiration_shift = int(sys.argv[3])
secret = sys.argv[4]

now = datetime.datetime.now(datetime.timezone.utc)
payload = {
    "role": role,
    "tenant": tenant,
    "iat": now,
    "exp": now + datetime.timedelta(seconds=expiration_shift),
}

print(jwt.encode(payload, secret, algorithm="HS256"))
PY
}

echo "================================================================"
echo " AUTH EDGE CASE TESTS"
echo "================================================================"

python3 -c "import jwt" 2>/dev/null || { echo "ERROR: PyJWT not installed. Run: pip install PyJWT"; exit 1; }

# 1) Expired token
EXPIRED_TOKEN="$(make_token "tenant_a_role" "tenant_a" "-300")"
assert_token "expired token" "$EXPIRED_TOKEN"
CODE="$(curl -s -o /tmp/auth_expired.json -w "%{http_code}" -H "Authorization: Bearer $EXPIRED_TOKEN" -H "Accept-Profile: tenant_a" "$BASE_URL/products")"
check_denied "Expired JWT should be denied" "$CODE"

# 2) Invalid signature (signed with wrong secret)
BAD_SIGNATURE_TOKEN="$(python3 - <<'PY'
import datetime
import jwt

now = datetime.datetime.now(datetime.timezone.utc)
payload = {
    "role": "tenant_a_role",
    "tenant": "tenant_a",
    "iat": now,
    "exp": now + datetime.timedelta(hours=1),
}
print(jwt.encode(payload, "wrong-secret-value", algorithm="HS256"))
PY
)"
CODE="$(curl -s -o /tmp/auth_bad_sig.json -w "%{http_code}" -H "Authorization: Bearer $BAD_SIGNATURE_TOKEN" -H "Accept-Profile: tenant_a" "$BASE_URL/products")"
check_denied "JWT with invalid signature should be denied" "$CODE"

# 3) Token without role claim
NO_ROLE_TOKEN="$(python3 - "$JWT_SECRET" <<'PY'
import datetime
import sys
import jwt

secret = sys.argv[1]
now = datetime.datetime.now(datetime.timezone.utc)
payload = {
    "tenant": "tenant_a",
    "iat": now,
    "exp": now + datetime.timedelta(hours=1),
}
print(jwt.encode(payload, secret, algorithm="HS256"))
PY
)"
CODE="$(curl -s -o /tmp/auth_no_role.json -w "%{http_code}" -H "Authorization: Bearer $NO_ROLE_TOKEN" -H "Accept-Profile: tenant_a" "$BASE_URL/products")"
check_denied "JWT without role claim should be denied" "$CODE"

# 4) Token with unknown role
UNKNOWN_ROLE_TOKEN="$(make_token "tenant_unknown_role" "tenant_a" "3600")"
assert_token "unknown role token" "$UNKNOWN_ROLE_TOKEN"
CODE="$(curl -s -o /tmp/auth_unknown_role.json -w "%{http_code}" -H "Authorization: Bearer $UNKNOWN_ROLE_TOKEN" -H "Accept-Profile: tenant_a" "$BASE_URL/products")"
check_denied "JWT with unknown DB role should be denied" "$CODE"

# 5) Malformed bearer token string
CODE="$(curl -s -o /tmp/auth_malformed.json -w "%{http_code}" -H "Authorization: Bearer not-a-jwt" -H "Accept-Profile: tenant_a" "$BASE_URL/products")"
check_denied "Malformed bearer token should be denied" "$CODE"

echo
echo "================================================================"
echo " RESULT: $PASS PASSED  |  $FAIL FAILED"
echo "================================================================"

[[ "$FAIL" -eq 0 ]]
