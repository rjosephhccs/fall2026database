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

The owner is a non-login, non-superuser role. Role creation is a credential-free template, not a dump of live cluster roles. The permissions template also revokes PUBLIC CREATE on schema `public`. V002 schema-qualifies stock tables and explicitly puts `pg_temp` last in trusted function search paths. These changes apply only to a new repository installation; the existing Mac database was read and exported, not migrated.

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

## Limits of verification

This validates restoration and the listed database behaviors. It is not a full multi-user concurrency test, application authentication test, production deployment assessment, or validation of real data. Java/Python services were not connected. Known design limitations and retained source permissions are documented in [SCHEMA.md](SCHEMA.md).

The older local Node/DBeaver draft and presentation files were not published as current implementation evidence: they describe a different four-table design and include incomplete starter setup. They remain available locally. This repository's baseline comes from the actual pgAdmin database.
