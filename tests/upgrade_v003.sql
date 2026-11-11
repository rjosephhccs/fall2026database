\set ON_ERROR_STOP on
-- Reconstruct the published V002 installation in a disposable empty database.
-- Never run this fixture on a live database; it creates fictional records.
BEGIN;
DO $$
BEGIN
    IF current_database() NOT LIKE 'inventory\_test\_%' ESCAPE '\' THEN
        RAISE EXCEPTION 'Use a disposable database named inventory_test_*';
    END IF;
END;
$$;
\ir ../database/security/00_roles.sql
\ir ../database/migrations/V001__live_schema_baseline.sql
\ir ../database/security/02_permissions.sql
\ir ../database/migrations/V002__trusted_function_resolution.sql
CREATE SCHEMA inventory_meta AUTHORIZATION inventory_owner;
CREATE TABLE inventory_meta.schema_migrations (
    version text PRIMARY KEY,
    description text NOT NULL,
    installed_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE inventory_meta.schema_migrations OWNER TO inventory_owner;
INSERT INTO inventory_meta.schema_migrations (version, description) VALUES
    ('V001', 'Live schema baseline, captured 2026-10-27; portable owner and separate ACLs'),
    ('V002', 'Trusted function resolution and schema-qualified stock relations');
SET LOCAL ROLE inventory_java;
INSERT INTO public.users (username, password_hash, role, first_name, email, is_active)
VALUES ('inew_upgrade_fictional_user', '!DISABLED-TEST-ONLY!', 'PRODUCT_MANAGER',
    'Fictional', 'upgrade-fixture@example.invalid', false);
RESET ROLE;
CREATE TEMP TABLE before_users AS SELECT to_jsonb(u) AS row_data FROM public.users u;
CREATE TEMP TABLE before_ledger AS SELECT to_jsonb(m) AS row_data FROM inventory_meta.schema_migrations m;
DO $$
BEGIN
    IF has_any_column_privilege('inventory_app', 'public.users', 'SELECT') THEN
        RAISE EXCEPTION 'V002 must start without Python user reads';
    END IF;
END;
$$;
COMMIT;

\ir ../database/upgrade_to_v003.sql

DO $$
BEGIN
    IF EXISTS (
        (SELECT row_data FROM pg_temp.before_users EXCEPT SELECT to_jsonb(u) FROM public.users u)
        UNION ALL
        (SELECT to_jsonb(u) FROM public.users u EXCEPT SELECT row_data FROM pg_temp.before_users)
    ) THEN
        RAISE EXCEPTION 'V003 changed existing user data';
    END IF;
    IF EXISTS (
        SELECT row_data FROM pg_temp.before_ledger
        EXCEPT SELECT to_jsonb(m) FROM inventory_meta.schema_migrations m
    ) OR (SELECT count(*) FROM inventory_meta.schema_migrations WHERE version = 'V003') <> 1 THEN
        RAISE EXCEPTION 'V003 failed to preserve and extend the migration ledger';
    END IF;
END;
$$;
\ir smoke.sql
\echo 'PASS: populated V002 upgrade preserves user data and existing ledger entries.'
