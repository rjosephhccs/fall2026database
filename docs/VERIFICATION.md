# Capture and verification record

## Source

- Database: `inventory_management_system`, schema `public`, on the user's Mac.
- Export date: October 27, 2026, 4:28 p.m. America/Chicago.
- PostgreSQL server and client: 18.6.
- pgAdmin reported the export **Finished**; the SQL dump has its completion marker.
- Export flags: plain SQL, schema only, no tablespaces, publications, subscriptions, or security labels; ownership and access-control statements retained for review.
- Private raw-export SHA-256: `7509b43844698d561a1b1bab14a11fd96023ea1fc6d8e8ebf5fec48d9cc96c3c`.
- The raw file stays under ignored `.private/exports/`; it is not published.

All six business tables were empty in the fresh restore before testing. No source table rows, login passwords, application password hashes, or pgAdmin connection profiles were copied into the package. SQL bodies, defaults, comments, and ACLs were reviewed as well as checked by the publication scanner.

## Packaging changes

V001 retains the exported business definitions. Local `postgres` ownership is mapped to `inventory_owner`; access grants/revokes are separated into the permissions template. Dump-specific TOC identifiers, export timestamps, and psql restrict-key wrappers are removed from the reviewed version. None of these are application records or credentials.

The owner is a non-login, non-superuser role. Role creation is a credential-free template, not a dump of live cluster roles. The permissions template also revokes PUBLIC CREATE on schema `public`. V002 schema-qualifies stock tables and explicitly puts `pg_temp` last in trusted function search paths. V003 adds column-limited user reads for Python through a new migration; published V001/V002 and the original security templates remain unchanged. The existing Mac database was read and exported, not migrated.

## Checks passed

`PG_BIN=/Library/PostgreSQL/18/bin bash scripts/verify.sh` completed successfully on October 27, 2026 using a disposable PostgreSQL 18.6 cluster and private Unix socket with no TCP listener.

- Clean transactional restore of roles, baseline, grants, and hardening.
- Six tables, six views, eleven functions, and four named triggers.
- Non-login role templates, function ownership, trusted search paths, and function execution matrix.
- Java user-management privileges and Python inventory-service denial of password-hash reads and direct stock/order writes.
- Pending orders leave stock unchanged; completion reduces stock from 10 to 7 and produces the expected 37.50 total and receipt.
- Inventory/order history protection, rejection of insufficient stock, and rollback of failed completion.
- Temporary tables cannot redirect stock-function writes after V002.
- A second setup refuses to overwrite an installed database.
- Publication scan of the final public text files.

The smoke fixtures are fictional and rolled back; the disposable cluster is then removed. PostgreSQL sequence increments are not transactional, so tests intentionally refuse non-test database names.

## V003 verification — November 11, 2026

`PG_BIN=/Library/PostgreSQL/18/bin bash scripts/verify.sh` passed on PostgreSQL 18.6 using a disposable cluster in a private temporary directory, a private Unix socket, and no TCP listener. The verifier explicitly clears `PGHOSTADDR` so an inherited address cannot override that socket. No connection or migration was made to the live Mac database.

- Fresh setup applies V001, V002, and V003 and records exactly those ledger versions.
- A separate populated V002 installation upgrades through `database/upgrade_to_v003.sql`, preserving its fictional user row and both existing migration-ledger entries.
- As `inventory_app`, a real query returns `user_id`, `username`, `role`, and `is_active`, including filtering and ordering by approved fields.
- Effective privileges allow SELECT on exactly those four columns, without whole-table SELECT, grant options, or user writes. Java retains its SELECT/INSERT/UPDATE access.
- Actual role queries reject `password_hash`, every other unapproved user column, `SELECT *`, and a password-hash predicate. Direct user INSERT/UPDATE/DELETE also fail with insufficient privilege.
- V003 rejects table-wide SELECT, direct password-hash grants, PUBLIC table/extra-column grants, inherited Java membership, membership permitting SET ROLE without inheritance, and delegable SELECT. Deliberate drift fixtures roll back.
- Repeating the grant migration succeeds; repeating the versioned upgrade wrapper fails. Repeating fresh setup still refuses to overwrite an existing database.
- Existing inventory, order, history, rollback, and temporary-table-shadowing checks pass after fresh setup and upgrade.
- Shell syntax, whitespace checks, and the public-file publication scan pass.

The upgrade fixture is committed only inside the disposable test database to model existing records; the entire temporary cluster is removed after verification. The automated suite tests role privileges, not external Python/Java service connections or login credentials.

## Limits of verification

This validates restoration and the listed database behaviors. It is not a full multi-user concurrency test, application authentication test, production deployment assessment, or validation of real data. Java/Python services were not connected. Known design limitations and retained source permissions are documented in [SCHEMA.md](SCHEMA.md).

The older local Node/DBeaver draft and presentation files were not published as current implementation evidence: they describe a different four-table design and include incomplete starter setup. They remain available locally. This repository's baseline comes from the actual pgAdmin database.
