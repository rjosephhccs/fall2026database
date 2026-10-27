-- Credential-free role template for a dedicated development installation.
-- Run as a PostgreSQL administrator. Roles are cluster-wide.
-- Existing roles are accepted only if they have no elevated attributes or memberships.
-- NOLOGIN roles can be granted to separately provisioned service logins later.
DO $roles$
DECLARE
    role_name text;
    existing pg_catalog.pg_roles%ROWTYPE;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['inventory_owner', 'inventory_admin', 'inventory_app', 'inventory_java']
    LOOP
        SELECT * INTO existing FROM pg_catalog.pg_roles WHERE rolname = role_name;
        IF FOUND THEN
            IF existing.rolsuper OR existing.rolcreatedb OR existing.rolcreaterole
               OR existing.rolreplication OR existing.rolbypassrls
               OR (role_name = 'inventory_owner' AND existing.rolcanlogin)
               OR EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members WHERE member = existing.oid)
            THEN
                RAISE EXCEPTION 'Role % has attributes or memberships requiring manual review. Use an isolated cluster.', role_name;
            END IF;
        ELSE
            EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', role_name);
        END IF;
    END LOOP;
END;
$roles$;

-- Do not add passwords here. An administrator can provision separate LOGIN roles
-- locally and grant ONLY the relevant group role. Never grant inventory_owner to
-- a service account. Configure passwords interactively with psql \password.
