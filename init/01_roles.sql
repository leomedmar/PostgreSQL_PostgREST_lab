-- ================================================================
--  01_roles.sql  --  Role hierarchy
-- ================================================================
--
--  Hierarchy:
--
--    postgres (superuser)
--    └── authenticator   (login, NOINHERIT -- PostgREST connects here)
--        ├── anon        (unauthenticated requests)
--        ├── tenant_a_role
--        └── tenant_b_role
--
--  NOINHERIT is essential: authenticator does not inherit permissions
--  from other roles. PostgREST switches role explicitly via SET ROLE
--  after validating the JWT.
-- ================================================================

-- Anonymous role: minimal access, no tenant schema access
CREATE ROLE anon NOLOGIN;

-- Tenant roles: no login, permissions scoped to their schema + RLS
CREATE ROLE tenant_a_role NOLOGIN;
CREATE ROLE tenant_b_role NOLOGIN;

-- PostgREST connection role (the only role with LOGIN)
CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD 'auth_pass_123';

-- authenticator may assume any of these roles via the JWT role claim
GRANT anon          TO authenticator;
GRANT tenant_a_role TO authenticator;
GRANT tenant_b_role TO authenticator;
