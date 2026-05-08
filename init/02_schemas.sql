-- ================================================================
--  02_schemas.sql  --  Per-tenant schemas (full isolation)
-- ================================================================
--
--  Each tenant has its own PostgreSQL schema.
--  No role may access another tenant's schema.
-- ================================================================

-- ── Harden the public schema ──────────────────────────────────
-- Prevents any role from creating objects in public by default
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- Revoke default CREATE on the database, but keep CONNECT for the
-- roles that PostgREST needs (authenticator and anon).
REVOKE CREATE ON DATABASE saas_lab FROM PUBLIC;
GRANT CONNECT ON DATABASE saas_lab TO authenticator;
GRANT CONNECT ON DATABASE saas_lab TO anon;

-- ── Tenant A ───────────────────────────────────────────────────
CREATE SCHEMA tenant_a;

-- Only tenant_a_role may use this schema
GRANT USAGE ON SCHEMA tenant_a TO tenant_a_role;

-- ── Tenant B ───────────────────────────────────────────────────
CREATE SCHEMA tenant_b;

GRANT USAGE ON SCHEMA tenant_b TO tenant_b_role;

-- ── anon has no access to any tenant schema ────────────────────
-- (no GRANT = implicitly denied)

-- ── Default search_path per role ──────────────────────────────
-- Prevents accidental resolution of public.* objects
ALTER ROLE tenant_a_role SET search_path TO tenant_a;
ALTER ROLE tenant_b_role SET search_path TO tenant_b;
