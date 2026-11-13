# INEW 2332 — Database Integration Update

**Date:** November 13, 2026  
**Database repository:** https://github.com/rjosephhccs/fall2026database  
**Python repository:** https://github.com/rjosephhccs/fall2026python

## Current status

The database administrator checked PostgreSQL 18 in pgAdmin 4 using the local database `inventory_management_system`. These checks verify database objects and effective permissions but **do not establish that Python, Java, or the frontend has connected successfully**.

### Database roles

- `inventory_admin`, `inventory_app` and `inventory_java` exist and can log in on the checked server.
- `inventory_python_login` was not found on the checked server. The Python `database.py` currently defaults to that username.
- `inventory_app` can connect to the checked database, use the `public` schema, and SELECT from `products`, `orders`, and `order_items`.
- `inventory_app` has column-level SELECT on `public.users(user_id, username, role, is_active)` but not table-wide SELECT on `users`.
- `inventory_java` can SELECT, INSERT and UPDATE `users` but lacks direct access to the product and order tables checked.
- No direct INSERT, UPDATE or DELETE grants were observed for `inventory_app` on the four checked tables.

### Stored functions

The six functions below were present in the `public` schema. All returned `true` for `inventory_app` EXECUTE privilege:

1. `add_order_item`
2. `complete_order`
3. `create_pending_order`
4. `create_product`
5. `record_stock_transaction`
6. `update_product_details`

These checks do not demonstrate that function calls with real arguments or business operations succeed.

## Required integration work

1. **Choose a test database:** The database repository's `docs/SETUP.md` documents `inventory_management_dev` as the separate development installation. The pgAdmin screenshots were from `inventory_management_system`. Do not rerun a fresh installation against the populated source database.
2. **Set up the Python login appropriately:** `docs/SETUP.md` recommends a separate `inventory_python_login` member of only `inventory_app`. Provision it in the correct PostgreSQL cluster using a unique, privately stored password. Avoid granting extra access to `users` or other tables.
3. **Configure Python securely:** Sandra should set `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and `JAVA_AUTH_URL` in a local `.env` or secret store. Never commit passwords or tokens. `localhost` is only suitable when the database is accessible on the backend's own machine or through an explicit local tunnel.
4. **Fix order ownership:** The Python `main.py` currently uses `temp_user_id = 1` for order creation. Replace it with the validated `user.user_id` from Java-backed authentication.
5. **Check function arguments:** The observed `create_pending_order` signature includes `p_notes text` in addition to `p_user_id integer`; confirm whether notes has a default or update the Python SQL call to pass an explicit argument.
6. **Test and document end to end:** Test the Python database login, Java JWT validation, GET products, product creation, inventory adjustment and order creation against development data; confirm resulting records in pgAdmin. Test frontend requests after backend tests pass.

## Database-side work completed vs outstanding

| Area | Status |
|---|---|
| Inventory roles identified | Verified in pgAdmin |
| Application table privileges | Verified in pgAdmin for four tables |
| Four user-column SELECT privileges | Verified for `inventory_app` |
| Six stored function EXECUTE privileges | Verified for `inventory_app` |
| Python application login and correct database selection | Not yet verified |
| Live FastAPI connectivity and authentication | Not yet verified |
| GET/POST operations and frontend integration | Not yet verified |

## Security note

Publishing code in GitHub does not deploy PostgreSQL, configure remote access, or make the database live. Avoid exposing the local database directly to the public internet.

## References

- [Database setup and migration instructions](https://github.com/rjosephhccs/fall2026database/blob/main/docs/SETUP.md)
- [Python database connection](https://github.com/rjosephhccs/fall2026python/blob/main/database.py)
- [Python authorization](https://github.com/rjosephhccs/fall2026python/blob/main/auth.py)
- [Python API endpoints](https://github.com/rjosephhccs/fall2026python/blob/main/main.py)
