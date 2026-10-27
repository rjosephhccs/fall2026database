\set ON_ERROR_STOP on
-- Run only after restoring all migrations and permissions into a new disposable
-- inventory_test_* database. Connect as its setup administrator (able to SET ROLE).
-- All fixtures are fictional; the password_hash sentinel cannot authenticate.
-- Rows roll back. PostgreSQL sequence increments do not, so never use a live DB.
BEGIN;
SET LOCAL search_path = pg_catalog, public, pg_temp;
SET LOCAL statement_timeout = '15s';
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
    actual text[];
    object_count integer;
BEGIN
    IF current_database() NOT LIKE 'inventory\_test\_%' ESCAPE '\' THEN
        RAISE EXCEPTION 'Use a disposable database named inventory_test_*';
    END IF;

    SELECT array_agg(c.relname::text ORDER BY c.relname) INTO actual
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'r';
    IF actual IS DISTINCT FROM ARRAY['inventory_transactions','order_items','orders','products','suppliers','users'] THEN
        RAISE EXCEPTION 'Expected the six exported tables';
    END IF;
    SELECT array_agg(c.relname::text ORDER BY c.relname) INTO actual
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind = 'v';
    IF actual IS DISTINCT FROM ARRAY['employee_order_summary','inventory_summary','inventory_value_report','low_stock_report','order_history','order_receipt'] THEN
        RAISE EXCEPTION 'Expected the six exported views';
    END IF;
    SELECT count(*) INTO object_count FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public';
    IF object_count <> 11 THEN RAISE EXCEPTION 'Expected eleven exported functions'; END IF;
    SELECT array_agg(t.tgname::text ORDER BY t.tgname) INTO actual
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal;
    IF actual IS DISTINCT FROM ARRAY['trg_protect_inventory','trg_protect_order_items','trg_protect_orders','trg_update_inventory'] THEN
        RAISE EXCEPTION 'Expected the four exported triggers';
    END IF;
END;
$$;

DO $$
DECLARE
    fn record;
    expected_app boolean;
    expected_admin boolean;
    role_name text;
BEGIN
    FOREACH role_name IN ARRAY ARRAY['inventory_owner','inventory_admin','inventory_app','inventory_java'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name
            AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolcanlogin) THEN
            RAISE EXCEPTION 'Expected a restricted NOLOGIN template role: %', role_name;
        END IF;
    END LOOP;
    FOR fn IN SELECT p.*, r.rolname AS owner_name FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN pg_roles r ON r.oid = p.proowner WHERE n.nspname = 'public'
    LOOP
        expected_app := fn.proname = ANY(ARRAY['add_order_item','cancel_pending_order','complete_order',
            'create_pending_order','create_product','record_stock_transaction','update_product_details']);
        expected_admin := fn.proname = ANY(ARRAY['complete_order','record_stock_transaction']);
        IF has_function_privilege('inventory_app', fn.oid, 'EXECUTE') IS DISTINCT FROM expected_app
            OR has_function_privilege('inventory_admin', fn.oid, 'EXECUTE') IS DISTINCT FROM expected_admin
            OR has_function_privilege('inventory_java', fn.oid, 'EXECUTE') THEN
            RAISE EXCEPTION 'Unexpected service execution privilege on %', fn.proname;
        END IF;
        IF EXISTS (SELECT 1 FROM aclexplode(COALESCE(fn.proacl, acldefault('f', fn.proowner)))
            WHERE grantee = 0 AND privilege_type = 'EXECUTE') THEN
            RAISE EXCEPTION 'PUBLIC can execute %', fn.proname;
        END IF;
        IF fn.owner_name <> 'inventory_owner' OR fn.prosecdef IS DISTINCT FROM expected_app THEN
            RAISE EXCEPTION 'Unexpected owner/security mode on %', fn.proname;
        END IF;
        IF NOT ('search_path=pg_catalog, public, pg_temp' = ANY(COALESCE(fn.proconfig, ARRAY[]::text[]))) THEN
            RAISE EXCEPTION 'Trusted search path missing on %; apply V002', fn.proname;
        END IF;
    END LOOP;
    IF NOT has_table_privilege('inventory_java','public.users','SELECT')
        OR NOT has_table_privilege('inventory_java','public.users','INSERT')
        OR NOT has_table_privilege('inventory_java','public.users','UPDATE')
        OR has_table_privilege('inventory_java','public.users','DELETE')
        OR has_table_privilege('inventory_app','public.users','SELECT')
        OR has_table_privilege('inventory_app','public.products','UPDATE')
        OR has_table_privilege('inventory_app','public.orders','INSERT')
        OR has_table_privilege('inventory_app','public.order_items','UPDATE')
        OR has_table_privilege('inventory_java','public.products','SELECT') THEN
        RAISE EXCEPTION 'Unexpected service table privileges';
    END IF;
    IF has_schema_privilege('inventory_app','public','CREATE')
        OR has_schema_privilege('inventory_java','public','CREATE') THEN
        RAISE EXCEPTION 'Runtime services must not create public objects';
    END IF;
END;
$$;

CREATE TEMP TABLE smoke_fixture (user_id integer, product_id integer, order_id integer, transaction_id integer);

SET LOCAL ROLE inventory_java;
INSERT INTO public.users (username, password_hash, role)
VALUES ('inew_smoke_fictional_user', '!DISABLED-TEST-ONLY!', 'PRODUCT_MANAGER')
RETURNING user_id AS test_user_id \gset
RESET ROLE;

SET LOCAL ROLE inventory_app;
SELECT public.create_product('Fictional smoke product','INEW-SMOKE-001','Disposable fixture',12.50,2)
    AS test_product_id \gset
SELECT public.record_stock_transaction(:test_product_id,'IN',10,'Fictional opening stock')
    AS test_transaction_id \gset
SELECT public.create_pending_order(:test_user_id,'Disposable smoke order') AS test_order_id \gset
SELECT public.add_order_item(:test_order_id,:test_product_id,3) AS test_item_id \gset
RESET ROLE;
INSERT INTO pg_temp.smoke_fixture VALUES (:test_user_id,:test_product_id,:test_order_id,:test_transaction_id);

DO $$
BEGIN
    IF (SELECT status FROM public.orders WHERE order_id = (SELECT order_id FROM pg_temp.smoke_fixture)) <> 'PENDING'
        OR (SELECT quantity FROM public.products WHERE product_id = (SELECT product_id FROM pg_temp.smoke_fixture)) <> 10 THEN
        RAISE EXCEPTION 'Adding a pending order must not deduct stock';
    END IF;
END;
$$;

SET LOCAL ROLE inventory_app;
SELECT public.complete_order(:test_order_id) AS completed_total \gset
RESET ROLE;
DO $$
DECLARE
    fixture pg_temp.smoke_fixture%ROWTYPE;
BEGIN
    SELECT * INTO STRICT fixture FROM pg_temp.smoke_fixture;
    IF (SELECT quantity FROM public.products WHERE product_id = fixture.product_id) <> 7
        OR (SELECT status FROM public.orders WHERE order_id = fixture.order_id) <> 'COMPLETED'
        OR (SELECT total_amount FROM public.orders WHERE order_id = fixture.order_id) <> 37.50
        OR (SELECT sum(line_total) FROM public.order_receipt WHERE order_id = fixture.order_id) <> 37.50
        OR (SELECT count(*) FROM public.inventory_transactions WHERE product_id = fixture.product_id AND transaction_type = 'OUT') <> 1 THEN
        RAISE EXCEPTION 'Order completion, receipt total, or stock movement is incorrect';
    END IF;
END;
$$;

-- Exercise privilege denial as the actual service role, not only catalog flags.
SET LOCAL ROLE inventory_app;
DO $$
DECLARE rejected boolean;
BEGIN
    rejected := false;
    BEGIN PERFORM password_hash FROM public.users; EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Inventory service could read password hashes'; END IF;
    rejected := false;
    BEGIN UPDATE public.products SET quantity = 99 WHERE sku = 'INEW-SMOKE-001';
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Inventory service could directly modify stock'; END IF;
    rejected := false;
    BEGIN UPDATE public.orders SET total_amount = 0;
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Inventory service could directly modify order totals'; END IF;
END;
$$;
RESET ROLE;

-- Exercise triggers as setup administrator so table privilege denial cannot
-- accidentally conceal a missing history-protection trigger.
DO $$
DECLARE
    fixture pg_temp.smoke_fixture%ROWTYPE;
    rejected boolean;
BEGIN
    SELECT * INTO STRICT fixture FROM pg_temp.smoke_fixture;
    rejected := false;
    BEGIN UPDATE public.inventory_transactions SET notes = 'Attempted edit' WHERE transaction_id = fixture.transaction_id;
    EXCEPTION WHEN raise_exception THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Inventory history update was accepted'; END IF;
    rejected := false;
    BEGIN DELETE FROM public.inventory_transactions WHERE transaction_id = fixture.transaction_id;
    EXCEPTION WHEN raise_exception THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Inventory history deletion was accepted'; END IF;
    rejected := false;
    BEGIN UPDATE public.orders SET notes = 'Attempted edit' WHERE order_id = fixture.order_id;
    EXCEPTION WHEN raise_exception THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Finalized order update was accepted'; END IF;
    rejected := false;
    BEGIN UPDATE public.order_items SET quantity = 4 WHERE order_id = fixture.order_id;
    EXCEPTION WHEN raise_exception THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Finalized order item update was accepted'; END IF;
END;
$$;

-- Function errors must leave stock and the pending order unchanged.
SET LOCAL ROLE inventory_app;
SELECT public.create_pending_order(:test_user_id,'Insufficient-stock fixture') AS rejected_order_id \gset
SELECT public.add_order_item(:rejected_order_id,:test_product_id,8) AS rejected_item_id \gset
DO $$
DECLARE
    rejected boolean := false;
    candidate integer;
BEGIN
    SELECT order_id INTO STRICT candidate FROM public.orders WHERE notes = 'Insufficient-stock fixture';
    BEGIN PERFORM public.complete_order(candidate); EXCEPTION WHEN raise_exception THEN rejected := true; END;
    IF NOT rejected THEN RAISE EXCEPTION 'Overselling was accepted'; END IF;
    IF (SELECT status FROM public.orders WHERE order_id = candidate) <> 'PENDING'
        OR (SELECT quantity FROM public.products WHERE sku = 'INEW-SMOKE-001') <> 7 THEN
        RAISE EXCEPTION 'Failed completion changed order or stock';
    END IF;
END;
$$;
SELECT public.cancel_pending_order(:rejected_order_id);
RESET ROLE;

-- A caller can create temporary names that shadow public relations. Definer
-- functions must still write the real schema after migration V002.
SET LOCAL ROLE inventory_app;
CREATE TEMP TABLE products (product_id integer, quantity integer);
CREATE TEMP TABLE inventory_transactions (transaction_id integer, product_id integer, transaction_type varchar(20), quantity integer, notes text);
INSERT INTO pg_temp.products VALUES (:test_product_id,999);
SELECT public.record_stock_transaction(:test_product_id,'IN',2,'Temp-shadow resistance fixture');
DO $$
BEGIN
    IF (SELECT quantity FROM public.products WHERE sku = 'INEW-SMOKE-001') <> 9
        OR (SELECT quantity FROM pg_temp.products) <> 999
        OR (SELECT count(*) FROM pg_temp.inventory_transactions) <> 0 THEN
        RAISE EXCEPTION 'Temporary relation shadowing redirected a stock transaction';
    END IF;
END;
$$;
RESET ROLE;

ROLLBACK;
\echo 'PASS: schema objects, owner/role privileges, pending/completed orders, receipts, history protection, failed completion rollback, and temporary-table shadowing.'
