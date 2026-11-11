# Setup and migrations

## Requirements

Use PostgreSQL 18 server/client tools. The source and verification environment use 18.6. Run installation as a PostgreSQL administrator on a development installation. Roles are cluster-wide, so the role template checks existing names for elevated attributes or inherited memberships and stops if manual review is required.

The repository intentionally includes no real data or usable login passwords. Java and Python services are separate integration work.

## New persistent development database

From the repository root, on a Mac with the standard PostgreSQL installer:

```sh
export PATH="/Library/PostgreSQL/18/bin:$PATH"
createdb -h localhost -p 5432 -U postgres -W inventory_management_dev
psql -X -h localhost -p 5432 -U postgres -W \
  -d inventory_management_dev -v ON_ERROR_STOP=1 -f database/setup.sql
```

Enter the existing administrator password privately when prompted. Adjust host, port, and administrator name to your installation. Do not place the password in a command, URL, repository file, screenshot, or chat message.

`setup.sql` is a **psql** script with relative include commands; use the terminal command above rather than pasting it into pgAdmin's Query Tool. It checks that the destination is empty, creates or validates roles, restores V001, applies permissions, V002, and V003, and records all three versions in `inventory_meta.schema_migrations`, all in one transaction. It deliberately refuses the source name `inventory_management_system` and the PostgreSQL maintenance databases. A repeat run fails without overwriting the installed database.

Open the new database in pgAdmin to inspect its `public` schema. A schema-only restore contains empty business tables; summary views may still return an aggregate row. The tests create their own fictional data and roll it back. Do not load production users or supplier contacts to demonstrate setup.

## Service roles and passwords

The template creates `inventory_owner`, `inventory_admin`, `inventory_app`, and `inventory_java` as non-login roles. Existing non-elevated service roles may already allow login; the script does not alter their passwords. No service should receive `inventory_owner` membership.

For a new installation, an administrator may create separately named login accounts and grant one relevant group role. Example in an administrator's local psql session:

```sql
CREATE ROLE inventory_python_login LOGIN;
GRANT inventory_app TO inventory_python_login;
CREATE ROLE inventory_java_login LOGIN;
GRANT inventory_java TO inventory_java_login;
```

Then run these psql commands and enter unique passwords at the private prompts:

```text
\password inventory_python_login
\password inventory_java_login
```

Keep service configuration in local environment settings or a secret store. These logins are not created by the automated setup. Review database CONNECT/TEMP privileges for your deployment; the package preserves the normal PostgreSQL defaults. `CREATE` on schema `public` is revoked from PUBLIC so untrusted roles cannot add objects to function search paths.

Give the Python login only `inventory_app`, with no independent `users` grants or additional service-role memberships. V003 checks `inventory_app` itself; a separate login with other privileges could still read more. Java's existing user-management access remains separate.

`inventory_admin` is an inventory operator, not a PostgreSQL superuser. Its captured grants permit direct product and supplier maintenance. The history-protection triggers continue to reject updates/deletes to inventory history even where a table grant exists. Use the stock function for accountable inventory changes; direct product quantity updates remain an administrative capability inherited from the source design.

## Version history

| Version | Change |
|---|---|
| V001 | Live schema export; `postgres` ownership mapped to `inventory_owner`; permissions separated into a reviewed template |
| V002 | Schema-qualifies stock relations and fixes function search paths to `pg_catalog, public, pg_temp` |
| V003 | Grants `inventory_app` SELECT on `users(user_id, username, role, is_active)` only; refuses unexpected broader privileges |

V002 prevents temporary tables from taking precedence over intended relations. V003 adds a column-level read grant for Python without changing Java grants, business data, or authentication. **Publishing these migrations does not apply them to the existing Mac database.** The original private export remains available for comparison.

## Upgrade an existing repository installation from V002

Use this path only for a database installed from this repository with exactly V001 and V002 in `inventory_meta.schema_migrations`. Review the destination and make a private backup before upgrading a persistent database. Do not rerun `setup.sql` or the published baseline on populated data.

From the repository root, using the setup administrator and your development database:

```sh
psql -X -h localhost -p 5432 -U postgres -W \
  -d inventory_management_dev -v ON_ERROR_STOP=1 \
  -f database/upgrade_to_v003.sql
```

This psql wrapper checks and locks the migration ledger, applies V003, and records V003 in one transaction. It refuses a missing/unexpected version history, a repeated upgrade, maintenance databases, and the live/source database name. If any check fails, neither the new grant nor the V003 ledger entry is committed. The migration SQL itself can be repeated safely, but the wrapper deliberately prevents recording the same version twice.

V003 refuses elevated `inventory_app` attributes, role memberships, table-wide `users` privileges, access to extra user columns, user writes, and grant options. Review such drift with the database administrator before retrying. It does not silently revoke permissions from Java, PUBLIC, or other roles. PostgreSQL permissions are additive: a column grant cannot restrict a wider table or inherited grant. See the [PostgreSQL GRANT reference](https://www.postgresql.org/docs/18/sql-grant.html).

## Verify Python user access

Run the isolated regression checks before publishing changes:

```sh
PG_BIN=/Library/PostgreSQL/18/bin bash scripts/verify.sh
python3 scripts/check_publication.py
```

After deliberately applying V003 to a development database, an administrator can inspect effective permissions without reading user records:

```sql
SELECT column_name,
       has_column_privilege('inventory_app', 'public.users', column_name, 'SELECT') AS can_select
FROM (VALUES ('user_id'), ('username'), ('role'), ('is_active'), ('password_hash')) AS fields(column_name);
-- Expected: true for the four approved fields; false for password_hash.

SELECT has_table_privilege('inventory_app', 'public.users', 'SELECT') AS whole_table_select;
-- Expected: false. A column grant does not require whole-table SELECT.
```

The Python backend must name its fields explicitly:

```sql
SELECT user_id, username, role, is_active
FROM public.users
ORDER BY user_id;
```

As `inventory_app`, `SELECT password_hash FROM public.users` and `SELECT * FROM public.users` must fail with `permission denied for table users`. Other user columns and direct INSERT/UPDATE/DELETE remain denied. The automated tests exercise these failures with fictional rows in a disposable cluster; do not run the smoke fixtures against a persistent database. Check the separately provisioned Python login too if it has additional grants or memberships.

## Future migrations

For a future change, add `V004__descriptive_name.sql` or the next unused version, review its effects, and test both a fresh setup and an upgrade from the previous version. Run each compatible migration together with its migration-ledger insert in a transaction. This repository uses explicit reviewed SQL, not an automatic migration discovery tool. Update `setup.sql` to include newly approved migrations and their ledger rows. Do not edit previously applied versions or rerun V001 on populated data.

Before applying V002 or later changes to the live source, make a private full backup, review role ownership and existing privileges, and test the upgrade separately. Publishing SQL to GitHub does not modify the Mac database.
