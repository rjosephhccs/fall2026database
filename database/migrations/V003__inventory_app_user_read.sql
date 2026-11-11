-- Forward migration: Python may read four user fields, never password_hash.
-- Apply through setup.sql or upgrade_to_v003.sql; published V001/V002 stay intact.
-- Fail on unexpected wider access instead of silently changing other role grants.
DO $migration$
DECLARE
    app_oid oid;
BEGIN
    SELECT oid INTO app_oid FROM pg_catalog.pg_roles
    WHERE rolname = 'inventory_app'
      AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
      AND NOT rolreplication AND NOT rolbypassrls;
    IF app_oid IS NULL OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_auth_members WHERE member = app_oid
    ) THEN
        RAISE EXCEPTION 'V003 requires a restricted inventory_app role without memberships; review role configuration.';
    END IF;

    -- Effective privilege checks include PUBLIC grants and table-wide access.
    -- Column REVOKE cannot override a table-level SELECT grant.
    IF pg_catalog.has_table_privilege(app_oid, 'public.users',
        'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN')
        OR pg_catalog.has_any_column_privilege(app_oid, 'public.users',
            'INSERT, UPDATE, REFERENCES, SELECT WITH GRANT OPTION')
        OR EXISTS (
            SELECT 1 FROM pg_catalog.pg_attribute
            WHERE attrelid = 'public.users'::pg_catalog.regclass
              AND attnum > 0 AND NOT attisdropped
              AND attname NOT IN ('user_id', 'username', 'role', 'is_active')
              AND pg_catalog.has_column_privilege(app_oid, attrelid, attnum, 'SELECT')
        ) THEN
        RAISE EXCEPTION 'V003 found broader users privileges for inventory_app; review existing grants before retrying.';
    END IF;

    GRANT SELECT (user_id, username, role, is_active)
        ON TABLE public.users TO inventory_app;

    IF NOT pg_catalog.has_schema_privilege(app_oid, 'public', 'USAGE')
        OR EXISTS (
            SELECT 1 FROM pg_catalog.unnest(ARRAY['user_id', 'username', 'role', 'is_active']) AS allowed(column_name)
            WHERE NOT pg_catalog.has_column_privilege(app_oid, 'public.users', column_name, 'SELECT')
        ) THEN
        RAISE EXCEPTION 'V003 could not grant all four user fields; run as the database setup administrator.';
    END IF;
END;
$migration$;
