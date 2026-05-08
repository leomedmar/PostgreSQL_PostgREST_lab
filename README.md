# PostgreSQL 13 + PostgREST — Multi-Tenant Lab

> **Version:** 2.0  
> **Stack:** PostgreSQL 13 · PostgREST v12.2.8 · Docker Compose · JWT (HS256)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Demo Mode](#3-demo-mode)
4. [Security Model](#4-security-model)
5. [Multi-Tenant Design](#5-multi-tenant-design)
6. [PostgREST API](#6-postgrest-api)
7. [Getting Started](#7-getting-started)
8. [Running the Tests](#8-running-the-tests)
9. [Production Considerations](#9-production-considerations)
10. [File Structure](#10-file-structure)

---

## 1. Overview

This laboratory validates a SaaS REST API architecture using **schema-per-tenant isolation** in PostgreSQL, exposed automatically via PostgREST. No application-layer code is required to generate the API.

### Goals

- Demonstrate strong multi-tenant data isolation using separate schemas
- Validate JWT authentication integrated with PostgreSQL roles
- Test Row Level Security (RLS) as a second line of defence
- Provide reproducible test scripts for QA sign-off
- Document the design for architecture review

---

## 2. Architecture

### Component Diagram

```
Client (curl/application)            Browser
      │                                  │
      │  HTTP: 3000                       │  HTTP: 8090
      │  Authorization: Bearer <jwt>      │
      │  Accept-Profile: tenant_a         │
      ▼                                  ▼
┌─────────────────────────────────┐  ┌─────────────────────────────────┐
│  PostgREST v12  (lab_postgrest) │  │  Dashboard  (lab_dashboard)     │
│                                 │  │                                 │
│  1. Validates JWT signature     │  │  Scenario status + PASS/FAIL    │
│  2. Extracts claim → role       │  │  Walkthrough runner             │
│  3. SET ROLE tenant_a_role      │  │  Test suite launcher            │
│  4. SET search_path = tenant_a  │  │  Live console output            │
└──────────────┬──────────────────┘  └─────────────────────────────────┘
               │ postgres://authenticator@:5432/saas_lab
               ▼
┌─────────────────────────────────┐
│  PostgreSQL 13  (lab_postgres)  │
│                                 │
│  schema tenant_a                │
│    ├── products  (RLS ON)       │
│    └── orders    (RLS ON)       │
│                                 │
│  schema tenant_b                │
│    ├── products  (RLS ON)       │
│    └── orders    (RLS ON)       │
└─────────────────────────────────┘
```

### Request Lifecycle

1. Client sends JWT in `Authorization: Bearer <token>` header
2. Client specifies target tenant via `Accept-Profile: tenant_x` header
3. PostgREST validates the JWT signature against `PGRST_JWT_SECRET`
4. PostgREST extracts the `role` claim and executes `SET ROLE` in PostgreSQL
5. PostgreSQL resolves the schema from `search_path`
6. Query executes under the tenant role's permissions + RLS policies
7. Only permitted rows are returned in the JSON response

---

## 3. Demo Mode

This repository includes a demo toolkit for meetings and architecture walkthroughs.

### Option A — Single Terminal Walkthrough

```bash
make demo-walkthrough
```

What it shows:

- Coloured step-by-step execution for all 5 isolation scenarios
- HTTP status codes and JSON previews for each request
- PASS/FAIL summary at the end

### Option B — Three Live Panels (tmux)

```bash
make demo-panes
```

Panel layout:

- Panel 1: scripted walkthrough
- Panel 2: live PostgREST logs
- Panel 3: live PostgreSQL tenant row counts

If `tmux` is not installed, run the scripts manually in 3 terminals:

```bash
bash demo/03_walkthrough.sh
bash demo/01_watch_logs.sh
bash demo/02_watch_db_state.sh
```

### Option C — Visual Dashboard (browser)

The dashboard runs as a Docker container — no Python dependencies needed on the host.

```bash
# Build once (only needed the first time, or after editing dashboard_server.py)
docker compose build dashboard

# The dashboard starts automatically with make up
make up
```

Then open `http://127.0.0.1:8090`.

What it shows:

- Live refresh every 3 seconds with a **Pause / Resume** button to freeze the display
- Scenario-by-scenario status (`PASS` / `FAIL`) with colour-coded ANSI output
- HTTP code and response preview for each scenario
- `Run Demo Walkthrough` button to execute the full demo from the browser
- Embedded console output with ANSI colours rendered
- Buttons to run all security/integrity suites:
  - `test-auth-edge`, `test-input-validation`, `test-cross-tenant-writes`
  - `test-query-hardening`, `test-api-surface`, `test-integrity-consistency`
  - `test-security-all`, `test-integrity-all`, `test-resilience`, `test-all`
  - `test-rebuild-baseline` (destructive; dashboard asks for confirmation)
- Per-suite status cards (`idle`, `running`, `passed`, `failed`) with live output panel

### Quick Execution (Short)

```bash
# 1) First time only: build the dashboard image
docker compose build dashboard

# 2) Start the full stack (PostgreSQL + PostgREST + Dashboard)
make up

# 3) Open the dashboard in the browser
#    http://127.0.0.1:8090

# 4) (Optional) Run the full test suite from the terminal
make test-all

# 5) (Optional, destructive) Rebuild from scratch and validate seed baseline
make test-rebuild-baseline
```

---

## 4. Security Model

### Role Hierarchy

```
postgres (superuser)
└── authenticator  (LOGIN, NOINHERIT) ← PostgREST connects as this role
    ├── anon            (no tenant access)
    ├── tenant_a_role   (schema tenant_a only)
    └── tenant_b_role   (schema tenant_b only)
```

`NOINHERIT` is critical: the `authenticator` role holds no permissions of its own. PostgREST explicitly switches roles via `SET ROLE` after JWT validation — it cannot accidentally access tenant data.

### Roles Reference

| Role | Login | Purpose |
|---|---|---|
| `postgres` | Yes | Superuser — direct DB administration only |
| `authenticator` | Yes | PostgREST connection role. `NOINHERIT` — no inherited permissions |
| `anon` | No | Unauthenticated requests. No access to any tenant schema |
| `tenant_a_role` | No | Full CRUD on `schema tenant_a` only |
| `tenant_b_role` | No | Full CRUD on `schema tenant_b` only |

### Defence Layers

**Layer 1 — Schema isolation**

The primary isolation mechanism. PostgreSQL denies access before evaluating any RLS policy:

```sql
GRANT USAGE ON SCHEMA tenant_a TO tenant_a_role;
-- tenant_b_role has no GRANT on schema tenant_a → access denied at schema level
```

**Layer 2 — Row Level Security (RLS)**

Defence-in-depth. Even if a role somehow reaches the wrong schema, RLS blocks all rows. `FORCE ROW LEVEL SECURITY` is applied to all tables so that even the superuser cannot bypass policies:

```sql
ALTER TABLE tenant_a.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_a.products FORCE ROW LEVEL SECURITY;

CREATE POLICY only_tenant_a ON tenant_a.products
  AS PERMISSIVE FOR ALL TO tenant_a_role
  USING (true) WITH CHECK (true);
```

**Layer 3 — Schema public hardening**

`CREATE` on the `public` schema is revoked from all roles. Only `authenticator` and `anon` retain `CONNECT` to the database:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON DATABASE saas_lab FROM PUBLIC;
GRANT CONNECT ON DATABASE saas_lab TO authenticator;
GRANT CONNECT ON DATABASE saas_lab TO anon;
```

### JWT Authentication

| Parameter | Detail |
|---|---|
| Algorithm | HS256 (HMAC-SHA256) |
| Secret | Minimum 32 characters. Set via `PGRST_JWT_SECRET` and `.env` |
| `role` claim | Mapped directly to a PostgreSQL role |
| `exp` claim | Validated automatically by PostgREST |
| Schema routing | `Accept-Profile: tenant_x` header on each request |

Token payload example:

```json
{
  "role": "tenant_a_role",
  "tenant": "tenant_a",
  "iat": 1715000000,
  "exp": 1715086400
}
```

---

## 5. Multi-Tenant Design

### Schema-per-Tenant vs Row-Level

| Criterion | Schema-per-Tenant *(this lab)* | Row-level (`tenant_id` column) |
|---|---|---|
| Isolation strength | Strong — independent schemas | Moderate — shared tables |
| Scalability | Hundreds of tenants | Thousands of tenants |
| Per-tenant backup | Simple (`pg_dump -n`) | Complex (requires filter) |
| Schema customisation | Possible per tenant | Shared structure |
| Operational complexity | Higher — N schemas to manage | Lower — single schema |

### Data Model (replicated per schema)

```sql
-- Same structure in tenant_a and tenant_b
products (id, name, price, stock, created_at)
orders   (id, customer_name, product_id FK, amount, status, created_at)
```

Status values for `orders.status`: `pending` · `processing` · `completed` · `cancelled`

---

## 6. PostgREST API

### Container Configuration

| Environment Variable | Value |
|---|---|
| `PGRST_DB_URI` | `postgres://authenticator:auth_pass_123@postgres:5432/saas_lab` |
| `PGRST_DB_SCHEMAS` | `tenant_a,tenant_b` |
| `PGRST_DB_ANON_ROLE` | `anon` |
| `PGRST_JWT_SECRET` | 32+ character secret (set in `.env`) |
| `PGRST_DB_POOL` | `10` |
| `PGRST_DB_MAX_ROWS` | `1000` — prevents full-table dumps in a single request |
| `PGRST_DB_EXTRA_SEARCH_PATH` | `public` — required for future RPC functions |
| `PGRST_SERVER_TIMING_ENABLED` | `true` — exposes query timing headers (disable in production) |

### Required Headers

All authenticated requests must include:

```
Authorization: Bearer <jwt_token>
Accept-Profile: tenant_a        # or tenant_b
```

Write operations additionally require:

```
Content-Profile: tenant_a       # or tenant_b
Content-Type: application/json
```

### Endpoint Reference

| Method | Endpoint | Operation |
|---|---|---|
| `GET` | `/products` | List all products for the tenant |
| `GET` | `/products?name=eq.Plano+Pro` | Filter by equality |
| `GET` | `/orders?status=eq.completed` | Filter by status |
| `GET` | `/orders?select=*,products(name,price)` | JOIN via resource embedding |
| `GET` | `/orders?order=created_at.desc&limit=10` | Sort and paginate |
| `POST` | `/products` | Insert a product |
| `PATCH` | `/orders?id=eq.1` | Update an order by ID |
| `DELETE` | `/products?id=eq.5` | Delete a product by ID |

### PostgREST Filter Operators

| Operator | Example | SQL Equivalent |
|---|---|---|
| `eq` | `?status=eq.pending` | `status = 'pending'` |
| `neq` | `?status=neq.cancelled` | `status != 'cancelled'` |
| `gt` / `gte` | `?amount=gte.100` | `amount >= 100` |
| `lt` / `lte` | `?amount=lte.500` | `amount <= 500` |
| `like` | `?name=like.Plan*` | `name LIKE 'Plan%'` |
| `in` | `?status=in.(pending,processing)` | `status IN (...)` |
| `is` | `?stock=is.null` | `stock IS NULL` |
| `order` | `?order=created_at.desc` | `ORDER BY created_at DESC` |
| `limit` / `offset` | `?limit=10&offset=20` | `LIMIT 10 OFFSET 20` |

---

## 7. Getting Started

### Prerequisites

- Docker Engine ≥ 20.10
- Docker Compose plugin (`docker compose`)
- Python 3.8+ with `pip install PyJWT` (for running tests from the host)
- `curl` (available on most Linux distributions)
- `make` (optional but recommended)

> The demo dashboard runs as a Docker container — no Python dependencies are required on the host to use it.

### First-Time Setup

```bash
# 1. Create the .env file (values match the docker-compose defaults)
cat > .env <<'EOF'
POSTGRES_DB=saas_lab
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres123
JWT_SECRET=lab-super-secret-jwt-key-32chars!!
EOF

# 2. Build the dashboard image and start the full stack
docker compose build dashboard
make up
```

### Verifying the Stack

After `make up`, confirm all three containers are running and healthy:

```bash
# Check container status
docker compose ps

# Tail logs
make logs
```

PostgreSQL initialisation scripts run automatically in alphabetical order from `./init/`. They only execute on first boot (empty volume). To re-run them: `make clean && make up`.

### Generate JWT Tokens

```bash
# Install once — make test-* targets handle this automatically
pip install PyJWT

# Print tokens and their decoded payloads
python3 tests/generate_tokens.py

# Export TOKEN_A and TOKEN_B as shell variables for manual curl calls
eval $(python3 tests/generate_tokens.py | grep 'export TOKEN_')
```

> The `JWT_SECRET` in `generate_tokens.py` must match `PGRST_JWT_SECRET` in `.env`.

### Quick Smoke Test

```bash
# TOKEN_A is already set if you ran the eval command above
curl -s \
  -H "Authorization: Bearer $TOKEN_A" \
  -H "Accept-Profile: tenant_a" \
  http://localhost:3000/products | python3 -m json.tool
```

---

## 8. Running the Tests

### Using Make (recommended)

```bash
make test-a          # Tenant A endpoints (GET, POST, JOIN)
make test-b          # Tenant B endpoints
make test-isolation  # Cross-tenant scenarios (all must fail)
make test-auth-edge  # JWT edge cases (expired, malformed, bad signature, role issues)
make test-input-validation # Constraint and payload validation checks
make test-resilience # Restart/recovery and post-restart isolation checks
make test-cross-tenant-writes # Denied POST/PATCH/DELETE across tenants
make test-query-hardening # Complex query bypass attempts across tenants
make test-api-surface # Schema/profile exposure and header hardening checks
make test-integrity-consistency # No partial persistence after failures + count consistency
make test-rebuild-baseline # Destructive rebuild + seed baseline verification
make test-security-all # Group: isolation + auth + write/query/api-surface hardening
make test-integrity-all # Group: validation + resilience + consistency checks
make test-all        # Full suite
make psql            # Open psql inside the postgres container
```

### Additional Test Suites

| Script | Focus | Expected Outcome |
|---|---|---|
| `04_test_auth_edge_cases.sh` | Expired token, invalid signature, missing role claim, unknown role, malformed bearer token | All requests denied (non-2xx) |
| `05_test_input_validation.sh` | SQL CHECK constraints, FK integrity, malformed JSON, required fields | Invalid writes rejected (non-2xx) |
| `06_test_resilience.sh` | PostgREST restart and recovery, data availability after restart, cross-tenant denial after restart | Recovery succeeds and isolation remains enforced |
| `07_test_cross_tenant_writes.sh` | Cross-tenant POST/PATCH/DELETE attempts | All cross-tenant writes denied |
| `08_test_query_bypass_hardening.sh` | Complex filters, ordering, embedding attempts against wrong tenant | Denied or empty responses only |
| `09_test_api_surface_security.sh` | Non-tenant profiles, missing/forged headers, unknown RPC endpoint | Requests rejected with non-2xx |
| `10_test_data_integrity_consistency.sh` | Count consistency before/after failures and cleanup | No unintended persistence drift |
| `11_test_rebuild_baseline.sh` | `make clean && make up` rebuild and baseline seed checks | Tenant seed counts match expected defaults |

### Security and Integrity Risk Matrix

| Risk / Threat | What could go wrong | Control layer | Test coverage | Pass criteria |
|---|---|---|---|---|
| Cross-tenant read access | Tenant token reads another tenant schema | Schema grants + role mapping + RLS | `03_test_cross_tenant.sh`, `test-isolation`, `test-security-all`, `test-all` | Cross-tenant reads denied (4xx) or empty data only |
| Cross-tenant write access | Tenant token inserts/updates/deletes in another tenant schema | Schema grants + role mapping + RLS | `07_test_cross_tenant_writes.sh`, `test-cross-tenant-writes`, `test-security-all`, `test-all` | Cross-tenant writes denied (4xx) |
| JWT bypass / malformed tokens | Expired, forged, malformed or invalid-role JWT accepted | PostgREST JWT validation + DB role checks | `04_test_auth_edge_cases.sh`, `test-auth-edge`, `test-security-all`, `test-all` | Invalid authentication requests denied (non-2xx) |
| Query-based bypass attempts | Crafted filters/order/embed bypass tenant boundary | Profile routing + role/schema permissions + RLS | `08_test_query_bypass_hardening.sh`, `test-query-hardening`, `test-security-all`, `test-all` | Requests denied (4xx) or empty result sets only |
| API surface/schema exposure | Access to non-tenant profiles or unsupported endpoints | `PGRST_DB_SCHEMAS` restriction + endpoint controls | `09_test_api_surface_security.sh`, `test-api-surface`, `test-security-all`, `test-all` | Non-tenant profile and unknown endpoint requests rejected |
| Invalid payload persistence | Bad input partially persisted despite rejection | SQL constraints + API validation | `05_test_input_validation.sh`, `test-input-validation`, `test-integrity-all`, `test-all` | Invalid writes rejected (non-2xx) with no drift |
| Restart/recovery security regression | Service recovers but isolation no longer enforced | PostgREST restart behaviour + DB policy continuity | `06_test_resilience.sh`, `test-resilience`, `test-integrity-all`, `test-all` | Service recovers and cross-tenant denial remains enforced |
| Data consistency drift over time | Failed writes or cleanup leave row counts inconsistent | Constraints + deterministic cleanup checks | `10_test_data_integrity_consistency.sh`, `test-integrity-consistency`, `test-integrity-all`, `test-all` | Baseline and final counts match expected values |
| Baseline seed corruption after rebuild | Fresh environment starts with unexpected seed state | Controlled init scripts + rebuild validation | `11_test_rebuild_baseline.sh`, `test-rebuild-baseline` | Rebuilt baseline matches seeded tenant counts |

### Test Scenarios — Isolation Suite (`03_test_cross_tenant.sh`)

| # | Scenario | Expected Result | Validates |
|---|---|---|---|
| 1 | `TOKEN_A` + `Accept-Profile: tenant_b` | HTTP 4xx | Schema barrier |
| 2 | `TOKEN_B` + `Accept-Profile: tenant_a` | HTTP 4xx | Schema barrier |
| 3 | No token (anon) accessing `tenant_a` | HTTP 4xx | JWT required |
| 4 | `TOKEN_A` accessing its own schema | HTTP 200 + data | Legitimate access works |
| 5 | `TOKEN_B` accessing its own schema | HTTP 200 + data | Legitimate access works |

### Validate RLS Directly in PostgreSQL

`FORCE ROW LEVEL SECURITY` is applied automatically to all tenant tables by `init/04_rls.sql` on first boot. To verify or test RLS behaviour interactively:

```sql
-- Connect to the container
docker compose exec postgres psql -U postgres -d saas_lab

-- Test as tenant_a_role
SET ROLE tenant_a_role;
SELECT * FROM tenant_a.orders;   -- returns rows
SELECT * FROM tenant_b.orders;   -- permission denied

-- Confirm FORCE RLS is active (relforcerowsecurity = true)
SELECT relname, rowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname IN ('products', 'orders')
  AND relnamespace IN (
    SELECT oid FROM pg_namespace WHERE nspname IN ('tenant_a', 'tenant_b')
  );
```

---

## 9. Production Considerations

### Security

- **TLS termination** — PostgREST does not terminate TLS. Place a reverse proxy (nginx, Caddy, Traefik) in front of it.
- **Secret management** — `JWT_SECRET` and database passwords must be injected via a secrets manager (HashiCorp Vault, AWS Secrets Manager, Kubernetes Secrets). Never hard-code them.
- **Token lifecycle** — Implement a dedicated authentication service (Auth0, Supabase Auth, custom service) that issues short-lived tokens. This lab generates tokens locally for testing only.
- **SSL on PostgreSQL connection** — Append `?sslmode=require` to the connection string in production.
- **Principle of least privilege** — Grant `SELECT` only by default; add `INSERT`/`UPDATE`/`DELETE` explicitly per endpoint.

### Scalability

- **Connection pooling** — Deploy PgBouncer between PostgREST and PostgreSQL to handle high concurrency efficiently.
- **Tenant onboarding** — Automate schema creation, role grants, and RLS policies via a parameterised SQL script or migrations tool.
- **Schema limits** — PostgreSQL handles hundreds of schemas comfortably. For thousands of tenants, consider the row-level model with a `tenant_id` column instead.

### Operations

- **Per-tenant backup** — `pg_dump -n tenant_x -Fc saas_lab > tenant_x.dump`
- **Monitoring** — PostgREST exposes Prometheus metrics; enable `pg_stat_statements` in PostgreSQL.
- **Migrations** — Use Flyway or Liquibase with per-schema migration paths.
- **Health probes** — Use `/ready` and `/live` endpoints from PostgREST for Kubernetes liveness/readiness probes.

### Known Lab Limitations

| Limitation | Production Approach |
|---|---|
| JWT generated locally without credential verification | Dedicated auth service |
| `authenticator` password in plain text in `docker-compose.yml` | Docker secrets / env injection |
| No TLS | Reverse proxy with SSL certificate |
| No sensitive field encryption | `pgcrypto` for PII fields |
| `PGRST_SERVER_TIMING_ENABLED: true` exposes query timing | Disable or restrict to internal networks |

---

## 10. File Structure

```
postgrest-lab/
├── docker-compose.yml          # PostgreSQL 13 + PostgREST v12 + Dashboard, isolated bridge network
├── Dockerfile                  # Dashboard container image (Python 3.12 + Docker CLI + PyJWT)
├── requirements.txt            # Python dependencies for the dashboard container
├── .env                        # JWT secret and DB credentials (not committed)
├── .gitignore                  # Excludes .env, __pycache__, *.pyc, *.log
├── Makefile                    # Convenience targets: up, down, test-*, psql, clean, demo-*
├── README.md                   # This document
│
├── init/                       # SQL scripts — executed by PostgreSQL on first boot only
│   ├── 01_roles.sql            # Role hierarchy (authenticator NOINHERIT)
│   ├── 02_schemas.sql          # Tenant schemas + GRANT isolation + public schema hardening
│   ├── 03_tables.sql           # products + orders tables per schema, FK indexes
│   ├── 04_rls.sql              # RLS enable + FORCE RLS + policies per schema
│   └── 05_seed.sql             # Test data for both tenants (stock values populated)
│
├── demo/
│   ├── 01_watch_logs.sh        # Live PostgREST logs panel
│   ├── 02_watch_db_state.sh    # Live tenant table snapshot panel
│   ├── 03_walkthrough.sh       # Guided visual walkthrough (5 scenarios)
│   ├── start_demo_panes.sh     # tmux launcher for 3-panel demo
│   └── dashboard_server.py     # Dashboard server (runs inside Docker container)
│
└── tests/
    ├── generate_tokens.py      # JWT token generator (requires PyJWT on the host)
    ├── 01_test_tenant_a.sh     # Tenant A API tests (GET, POST, JOIN, filter)
    ├── 02_test_tenant_b.sh     # Tenant B API tests
    ├── 03_test_cross_tenant.sh # Isolation suite: 5 scenarios with PASS/FAIL output
    ├── 04_test_auth_edge_cases.sh # JWT/authentication negative cases
    ├── 05_test_input_validation.sh # Invalid payload and constraint tests
    ├── 06_test_resilience.sh   # Recovery and post-restart isolation checks
    ├── 07_test_cross_tenant_writes.sh # Cross-tenant write-denial checks
    ├── 08_test_query_bypass_hardening.sh # Complex query bypass hardening
    ├── 09_test_api_surface_security.sh # API surface and profile/header hardening
    ├── 10_test_data_integrity_consistency.sh # Integrity consistency around failures
    └── 11_test_rebuild_baseline.sh # Destructive rebuild + seed baseline verification
```

---
