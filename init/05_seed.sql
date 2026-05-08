-- ================================================================
--  05_seed.sql  --  Test data
-- ================================================================

-- ── Tenant A  (company: "Acme Software") ──────────────────────
INSERT INTO tenant_a.products (name, price, stock) VALUES
    ('Starter Plan',    49.90, 100),
    ('Pro Plan',       149.90,  50),
    ('Enterprise Plan',499.90,  10);

INSERT INTO tenant_a.orders (customer_name, product_id, amount, status) VALUES
    ('Carlos Ferreira', 1,  49.90, 'completed'),
    ('Maria Silva',     2, 149.90, 'completed'),
    ('Joao Costa',      2, 149.90, 'processing'),
    ('Ana Rodrigues',   3, 499.90, 'pending');

-- ── Tenant B  (company: "Beta Cloud") ─────────────────────────
INSERT INTO tenant_b.products (name, price, stock) VALUES
    ('Storage 100GB',  9.90, 200),
    ('Storage 1TB',   49.90,  75),
    ('Compute XL',   199.90,  20);

INSERT INTO tenant_b.orders (customer_name, product_id, amount, status) VALUES
    ('Alpha Ltd',          1,   9.90, 'completed'),
    ('Tech Innovations',   2,  49.90, 'completed'),
    ('Global Corp',        3, 199.90, 'processing'),
    ('StartUp XYZ',        2,  49.90, 'pending');
