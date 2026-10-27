\set ON_ERROR_STOP on
-- psql entry point: one transaction, one new empty database, no live data changes.
BEGIN;
DO $guard$
BEGIN
    IF current_database() IN ('postgres', 'template0', 'template1', 'inventory_management_system') THEN
        RAISE EXCEPTION 'Use a new empty database; the live/source database is deliberately refused.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND n.nspname NOT LIKE 'pg_toast%' AND n.nspname NOT LIKE 'pg_temp%'
    ) OR EXISTS (
        SELECT 1 FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
    ) THEN
        RAISE EXCEPTION 'Database is not empty; setup will not overwrite it.';
    END IF;
END;
$guard$;
\ir security/00_roles.sql
\ir migrations/V001__live_schema_baseline.sql
\ir security/02_permissions.sql
\ir migrations/V002__trusted_function_resolution.sql
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
COMMIT;
