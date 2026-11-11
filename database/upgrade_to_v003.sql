\set ON_ERROR_STOP on
-- psql entry point for a repository installation already at V002.
-- The grant and ledger entry commit together; no user rows are modified.
BEGIN;
DO $guard$
BEGIN
    IF current_database() IN ('postgres', 'template0', 'template1', 'inventory_management_system') THEN
        RAISE EXCEPTION 'V003 upgrade refuses maintenance and live/source databases; use a reviewed repository installation.';
    END IF;
    IF pg_catalog.to_regclass('inventory_meta.schema_migrations') IS NULL THEN
        RAISE EXCEPTION 'V003 requires the repository V001/V002 migration ledger; do not run setup on an existing database.';
    END IF;
END;
$guard$;
LOCK TABLE inventory_meta.schema_migrations IN EXCLUSIVE MODE;
DO $versions$
BEGIN
    IF (SELECT array_agg(version ORDER BY version) FROM inventory_meta.schema_migrations)
        IS DISTINCT FROM ARRAY['V001', 'V002']::text[] THEN
        RAISE EXCEPTION 'V003 requires exactly V001 and V002 in the migration ledger; already applied or unexpected version history.';
    END IF;
END;
$versions$;
\ir migrations/V003__inventory_app_user_read.sql
INSERT INTO inventory_meta.schema_migrations (version, description) VALUES
    ('V003', 'Column-limited user reads for the Python inventory service');
COMMIT;
