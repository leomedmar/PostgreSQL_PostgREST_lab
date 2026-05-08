#!/usr/bin/env bash
set -euo pipefail

echo "=============================================================="
echo " PostgREST Live Logs"
echo "=============================================================="
echo "Press Ctrl+C to stop this panel."
echo

docker compose logs -f postgrest
