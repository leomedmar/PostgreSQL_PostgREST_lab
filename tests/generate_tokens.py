#!/usr/bin/env python3
"""
generate_tokens.py  --  JWT token generator for the PostgREST lab
==================================================================

Dependency:  pip install PyJWT

Usage:
    python3 generate_tokens.py

Export tokens as shell environment variables:
    eval $(python3 tests/generate_tokens.py | grep 'export TOKEN_')
"""

import sys
import json
import datetime
import os

try:
    import jwt
except ImportError:
    print("Missing dependency. Install with: pip install PyJWT")
    sys.exit(1)

# Must match PGRST_JWT_SECRET in .env and docker-compose.yml
JWT_SECRET = os.getenv("JWT_SECRET", "lab-super-secret-jwt-key-32chars!!")

EXPIRY_HOURS = 24


def generate(role: str, tenant: str) -> str:
    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "role":   role,
        "tenant": tenant,
        "iat": now,
        "exp": now + datetime.timedelta(hours=EXPIRY_HOURS),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def decode_and_show(token: str) -> None:
    decoded = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    print(json.dumps(decoded, indent=2, default=str))


if __name__ == "__main__":
    token_a = generate("tenant_a_role", "tenant_a")
    token_b = generate("tenant_b_role", "tenant_b")

    print("=" * 60)
    print("TENANT A TOKEN")
    print("=" * 60)
    print(token_a)
    print()
    print("Decoded payload:")
    decode_and_show(token_a)

    print()
    print("=" * 60)
    print("TENANT B TOKEN")
    print("=" * 60)
    print(token_b)
    print()
    print("Decoded payload:")
    decode_and_show(token_b)

    print()
    print("Export for test scripts:")
    print(f'  export TOKEN_A="{token_a}"')
    print(f'  export TOKEN_B="{token_b}"')
