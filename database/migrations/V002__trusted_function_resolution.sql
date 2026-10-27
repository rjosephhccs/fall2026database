-- Forward migration: protect function resolution from caller-created temporary tables.
-- This changes the repository installation only; it has NOT been applied to the live Mac database.
-- Preserve function signatures, owners, ACLs, and business rules.

CREATE OR REPLACE FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_transaction_id INTEGER;
BEGIN
    INSERT INTO public.inventory_transactions (
        product_id,
        transaction_type,
        quantity,
        notes
    )
    VALUES (
        p_product_id,
        p_transaction_type,
        p_quantity,
        p_notes
    )
    RETURNING transaction_id
    INTO v_transaction_id;

    RETURN v_transaction_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_inventory_quantity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.transaction_type = 'IN' THEN
        UPDATE public.products
        SET quantity = quantity + NEW.quantity
        WHERE product_id = NEW.product_id;

    ELSIF NEW.transaction_type = 'OUT' THEN
        UPDATE public.products
        SET quantity = quantity - NEW.quantity
        WHERE product_id = NEW.product_id
          AND quantity >= NEW.quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Insufficient stock for product ID %',
                NEW.product_id;
        END IF;

    ELSIF NEW.transaction_type = 'ADJUSTMENT' THEN
        UPDATE public.products
        SET quantity = NEW.quantity
        WHERE product_id = NEW.product_id;
    ELSE
        RAISE EXCEPTION
            'Invalid transaction type: %',
            NEW.transaction_type;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION public.add_order_item(p_order_id integer, p_product_id integer, p_quantity integer) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.cancel_pending_order(p_order_id integer) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.complete_order(p_order_id integer) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.create_pending_order(p_user_id integer, p_notes text) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.protect_inventory_history() SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.protect_order_items() SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.protect_order_records() SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text) SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.update_inventory_quantity() SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION public.update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer) SET search_path = pg_catalog, public, pg_temp;
