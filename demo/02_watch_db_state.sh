#!/usr/bin/env bash
set -euo pipefail

INTERVAL_SECONDS="${INTERVAL_SECONDS:-2}"

print_snapshot() {
  clear
  echo "=============================================================="
  echo " PostgreSQL Tenant Snapshot"
  echo "=============================================================="
  echo "Updated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo

  docker compose exec -T postgres psql -U postgres -d saas_lab -c "
SELECT
  'tenant_a.products' AS table_name,
  COUNT(*)::INT AS rows
FROM tenant_a.products
UNION ALL
SELECT 'tenant_a.orders', COUNT(*)::INT FROM tenant_a.orders
UNION ALL
SELECT 'tenant_b.products', COUNT(*)::INT FROM tenant_b.products
UNION ALL
SELECT 'tenant_b.orders', COUNT(*)::INT FROM tenant_b.orders
ORDER BY table_name;
"

  echo
  docker compose exec -T postgres psql -U postgres -d saas_lab -c "
SELECT 'tenant_a' AS tenant, MAX(id) AS latest_product_id FROM tenant_a.products
UNION ALL
SELECT 'tenant_b' AS tenant, MAX(id) AS latest_product_id FROM tenant_b.products
ORDER BY tenant;
"

  echo
  echo "Press Ctrl+C to stop this panel."
}

while true; do
  print_snapshot
  sleep "$INTERVAL_SECONDS"
done
