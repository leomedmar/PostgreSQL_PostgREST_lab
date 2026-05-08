-- ================================================================
--  03_tables.sql  --  Tables per schema
-- ================================================================
--
--  Each tenant has the same data model (products + orders).
--  The tables are physically separate in distinct schemas.
-- ================================================================

-- ── Tenant A ───────────────────────────────────────────────────
CREATE TABLE tenant_a.products (
    id         SERIAL PRIMARY KEY,
    name       TEXT           NOT NULL,
    price      NUMERIC(10,2)  NOT NULL CHECK (price >= 0),
    stock      INT                     CHECK (stock >= 0),
    created_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE tenant_a.orders (
    id            SERIAL PRIMARY KEY,
    customer_name TEXT           NOT NULL,
    product_id    INT            REFERENCES tenant_a.products(id),
    amount        NUMERIC(10,2)  NOT NULL CHECK (amount > 0),
    status        TEXT           NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending','processing','completed','cancelled')),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Full CRUD for tenant_a_role
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_a.products TO tenant_a_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_a.orders   TO tenant_a_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA tenant_a   TO tenant_a_role;

CREATE INDEX ON tenant_a.orders (product_id);
CREATE INDEX ON tenant_a.orders (status);
CREATE INDEX ON tenant_a.orders (created_at);

-- ── Tenant B ───────────────────────────────────────────────────
CREATE TABLE tenant_b.products (
    id         SERIAL PRIMARY KEY,
    name       TEXT           NOT NULL,
    price      NUMERIC(10,2)  NOT NULL CHECK (price >= 0),
    stock      INT                     CHECK (stock >= 0),
    created_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE TABLE tenant_b.orders (
    id            SERIAL PRIMARY KEY,
    customer_name TEXT           NOT NULL,
    product_id    INT            REFERENCES tenant_b.products(id),
    amount        NUMERIC(10,2)  NOT NULL CHECK (amount > 0),
    status        TEXT           NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending','processing','completed','cancelled')),
    created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_b.products TO tenant_b_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON tenant_b.orders   TO tenant_b_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA tenant_b   TO tenant_b_role;

CREATE INDEX ON tenant_b.orders (product_id);
CREATE INDEX ON tenant_b.orders (status);
CREATE INDEX ON tenant_b.orders (created_at);
