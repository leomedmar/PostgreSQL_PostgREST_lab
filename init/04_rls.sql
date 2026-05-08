-- ================================================================
--  04_rls.sql  --  Row Level Security (second line of defence)
-- ================================================================
--
--  Primary isolation is achieved by separate schemas.
--  RLS is an additional defence-in-depth layer: even if a role
--  somehow reaches the wrong schema (e.g. due to a misconfiguration),
--  the policies block all rows.
--
--  Note: PostgreSQL superusers bypass RLS by default.
--  To enforce RLS for superusers use FORCE ROW LEVEL SECURITY.
-- ================================================================

-- ── Enable RLS ─────────────────────────────────────────────────
ALTER TABLE tenant_a.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_a.orders   ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_b.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_b.orders   ENABLE ROW LEVEL SECURITY;

-- FORCE RLS so that even the table owner (postgres superuser)
-- cannot bypass policies when accessing these tables.
ALTER TABLE tenant_a.products FORCE ROW LEVEL SECURITY;
ALTER TABLE tenant_a.orders   FORCE ROW LEVEL SECURITY;
ALTER TABLE tenant_b.products FORCE ROW LEVEL SECURITY;
ALTER TABLE tenant_b.orders   FORCE ROW LEVEL SECURITY;

-- ── Tenant A policies ──────────────────────────────────────────
-- Only tenant_a_role may read or modify rows in these tables

CREATE POLICY only_tenant_a ON tenant_a.products
    AS PERMISSIVE FOR ALL TO tenant_a_role
    USING (true) WITH CHECK (true);

CREATE POLICY only_tenant_a ON tenant_a.orders
    AS PERMISSIVE FOR ALL TO tenant_a_role
    USING (true) WITH CHECK (true);

-- ── Tenant B policies ──────────────────────────────────────────
CREATE POLICY only_tenant_b ON tenant_b.products
    AS PERMISSIVE FOR ALL TO tenant_b_role
    USING (true) WITH CHECK (true);

CREATE POLICY only_tenant_b ON tenant_b.orders
    AS PERMISSIVE FOR ALL TO tenant_b_role
    USING (true) WITH CHECK (true);
