# Export the database from the Mac

The project database identified in pgAdmin is `inventory_management_system` on `localhost:5432`. The older `inventory-database` starter uses a different database and port; its SQL is not a substitute for this live database export.

The successful export was saved on October 27, 2026 at 4:28 p.m. Central in the ignored `.private/exports/live_schema_v2.sql`. Its header reports PostgreSQL server and `pg_dump` version 18.6. Review exports locally before copying approved definitions into versioned SQL. Do not share passwords, connection files, screenshots containing credentials, or records from the live database.

## pgAdmin export

Right-click **inventory_management_system → Backup…**. Use these settings:

| Setting | Value |
|---|---|
| Filename | An absolute path ending in `.private/exports/live_schema.sql` |
| Format | Plain |
| Only schemas | Yes |
| Only data | No |
| Pre-data / Post-data | Include both |
| Data / Blobs | Exclude |
| Do not save: Owner | No; retain ownership for review |
| Do not save: Privileges | No; retain grants and revokes |
| Do not save: Tablespaces | Yes |
| Include CREATE / DROP DATABASE | No |
| Object selection | The complete project database; no individual-table filter |

Choose **Backup**, then inspect the **Processes** result. A nonempty file alone does not establish success. pgAdmin uses `pg_dump`; post-data contains definitions such as triggers and indexes. See the official [Backup dialog documentation](https://www.pgadmin.org/docs/pgadmin4/latest/backup_dialog.html).

The first attempt using pgAdmin's bundled executable was killed and failed. Setting pgAdmin's PostgreSQL binary directory to `/Library/PostgreSQL/18/bin` allowed the subsequent export to succeed. For another machine, verify its installed PostgreSQL client before changing the binary directory. A killed process is a failed export.

## Terminal alternative

From the repository folder, replace `your_admin_role` with the local PostgreSQL role. Enter its password only in the terminal prompt. Keep the server running.

```sh
mkdir -p .private/exports
chmod 700 .private .private/exports
umask 077
/Library/PostgreSQL/18/bin/pg_dump \
  --host=localhost \
  --port=5432 \
  --username=your_admin_role \
  --password \
  --dbname=inventory_management_system \
  --schema-only \
  --format=plain \
  --no-tablespaces \
  --file=.private/exports/live_schema.sql
```

Use a compatible client version and require exit status zero. `--schema-only` exports definitions without table rows or sequence values. Ownership and access permissions remain because this command does not use `--no-owner` or `--no-acl`. A single-database export does not create cluster roles; prepare role templates separately. See the [PostgreSQL 18 `pg_dump` reference](https://www.postgresql.org/docs/18/app-pgdump.html).

Do not use **Backup Globals**, **Backup Server**, or `pg_dumpall` for the GitHub package. Do not add a data dump or copy PostgreSQL's storage directory.

## Review and version the result

1. Check that the export includes every expected project table, sequence, constraint, index, function, view, and trigger. Compare the result with pgAdmin's object tree.
2. Read routine bodies, defaults, comments, foreign-server settings, and grants. Schema-only exports can still contain embedded secrets or identifying text. Remove or replace sensitive values in the publishable copy; keep the original private.
3. Review every referenced owner and grantee. Create password-free role templates containing only required roles, attributes, and memberships. A role name is not a password. Do not export password hashes or copy personal login credentials into those templates.
4. Treat the first reviewed export as the baseline for a new, empty database. Preserve its dependency order. Record subsequent changes in new numbered migration files; do not overwrite an already applied migration.
5. Restore into a disposable database with the reviewed roles and run the verification scripts. Compare object counts and privilege behavior. Never test a restore against the working `inventory_management_system` database.
6. Inspect the exact staged changes before committing. `.gitignore` prevents accidental additions of matching untracked files; it does not remove files already tracked by Git.

Record the export date, server/client versions, any redactions or ownership changes, and restore-test outcome alongside the baseline. An export is a snapshot; later changes made in pgAdmin must also be captured in versioned SQL.

## How this export was packaged

The private raw export retains `postgres` ownership and the original access-control statements. The published baseline maps object ownership to the non-login role `inventory_owner`. The exported grants and revokes are kept in a separate security template, with password-free role setup. V002 records function search-path hardening and schema-qualified stock operations; the permissions template removes public permission to create objects in `public`. These changes are versioned for a new installation and do not modify the source database on the Mac. See [the schema reference](SCHEMA.md) for behavior and remaining limitations.
