# Fall 2026 Capstone Project for Database

## INEW 2332 — Inventory Management System

Versioned PostgreSQL database work exported from the live Mac database `inventory_management_system` on October 27, 2026. The reviewed export contains **6 tables, 6 identity sequences, 11 functions, 4 triggers, and 6 views** in schema `public`. It includes no application rows, user password hashes, connection passwords, or pgAdmin settings.

This package captures the actual pgAdmin database. The older local `inventory-database` Node/DBeaver draft used a different schema and is not the source of this installation.

| Location | Purpose |
|---|---|
| `database/migrations/V001__live_schema_baseline.sql` | Live structure and original business logic, with a portable non-login owner |
| `database/migrations/V002__trusted_function_resolution.sql` | Explicit trusted search paths and schema-qualified stock operations |
| `database/security/00_roles.sql` | Credential-free PostgreSQL role template |
| `database/security/02_permissions.sql` | Reviewed grants captured from the live database |
| `database/setup.sql` | Transactional installation into a new empty database |
| `docs/SCHEMA.md` | Tables, relationships, functions, triggers, views, and integration notes |
| `docs/SETUP.md` | Installation, permissions, credentials, and future migrations |
| `docs/EXPORT_FROM_PGADMIN.md` | Repeatable private schema export procedure |
| `docs/VERIFICATION.md` | Source provenance and verification results |
| `tests/smoke.sql` | Fictional-fixture behavior and permission checks |

### Verify on a Mac

Requires the PostgreSQL 18 command-line tools and Python 3. No Node application or database password is required for this isolated check.

```sh
PG_BIN=/Library/PostgreSQL/18/bin bash scripts/verify.sh
python3 scripts/check_publication.py
```

The verification script creates a disposable PostgreSQL cluster with a private Unix socket, restores the database, runs checks, and removes the temporary cluster. It never connects to the live Mac database. For a persistent development copy, follow [setup instructions](docs/SETUP.md).

### Database workflow

The Python service uses `inventory_app` privileges to create products, record stock movements, create pending orders, add items, and complete or cancel orders. Java uses `inventory_java` privileges for user-management and authentication data. `inventory_admin` has the captured inventory-management grants; `inventory_owner` owns the installed objects and cannot log in.

Employee authorization remains an application responsibility. The database checks that an order creator is an active `PRODUCT_MANAGER`, but a shared service connection cannot establish which employee made an HTTP request. Read the [schema notes and limitations](docs/SCHEMA.md) before integration.

### Versioning and privacy

Keep `V001` and `V002` immutable after publication. Add a new numbered migration for each later change and test it on a disposable copy first. Do not apply the baseline to the already populated Mac database.

Raw exports remain under ignored `.private/exports/`. Never commit data backups, CSV results, connection files, `.env` secrets, password hashes, or pgAdmin profiles. Schema exports also require review because SQL bodies and comments can contain secrets. [PostgreSQL documents the schema-only export behavior](https://www.postgresql.org/docs/18/app-pgdump.html).
