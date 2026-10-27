-- Immutable baseline exported from the Mac on 2026-10-27.
-- PostgreSQL 18.6; structure only; original SQL bodies retained.
-- Owner mapped from postgres to inventory_owner; ACLs moved to security/02_permissions.sql.
-- Apply through database/setup.sql to a NEW EMPTY database only.
--
-- PostgreSQL database dump
--


-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: add_order_item(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.add_order_item(p_order_id integer, p_product_id integer, p_quantity integer) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_status VARCHAR(20);
    v_price NUMERIC(10,2);
    v_item_id INTEGER;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be positive';
    END IF;

    SELECT status INTO v_status
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND OR v_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Order does not exist or is not pending';
    END IF;

    SELECT unit_price INTO v_price
    FROM public.products
    WHERE product_id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found';
    END IF;

    INSERT INTO public.order_items (
        order_id,
        product_id,
        quantity,
        unit_price
    )
    VALUES (
        p_order_id,
        p_product_id,
        p_quantity,
        v_price
    )
    RETURNING order_item_id INTO v_item_id;

    RETURN v_item_id;
END;
$$;


ALTER FUNCTION public.add_order_item(p_order_id integer, p_product_id integer, p_quantity integer) OWNER TO inventory_owner;

--
-- Name: cancel_pending_order(integer); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.cancel_pending_order(p_order_id integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
    UPDATE public.orders
    SET status = 'CANCELLED'
    WHERE order_id = p_order_id
      AND status = 'PENDING';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Only existing pending orders can be cancelled';
    END IF;
END;
$$;


ALTER FUNCTION public.cancel_pending_order(p_order_id integer) OWNER TO inventory_owner;

--
-- Name: complete_order(integer); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.complete_order(p_order_id integer) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_status VARCHAR(20);
    v_total NUMERIC(12,2) := 0;
    v_item_count INTEGER := 0;
    v_item RECORD;
BEGIN
    -- Lock the order to prevent duplicate completion
    SELECT status
    INTO v_status
    FROM public.orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Order % does not exist', p_order_id;
    END IF;

    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Order % is not pending', p_order_id;
    END IF;

    -- Check inventory and lock products
    FOR v_item IN
        SELECT
            oi.product_id,
            oi.quantity,
            oi.unit_price,
            p.quantity AS available_quantity
        FROM public.order_items oi
        JOIN public.products p
            ON oi.product_id = p.product_id
        WHERE oi.order_id = p_order_id
        ORDER BY oi.product_id
        FOR UPDATE OF p
    LOOP
        v_item_count := v_item_count + 1;

        IF v_item.available_quantity < v_item.quantity THEN
            RAISE EXCEPTION
                'Insufficient stock for product %. Available: %, Required: %',
                v_item.product_id,
                v_item.available_quantity,
                v_item.quantity;
        END IF;

        v_total := v_total +
            (v_item.quantity * v_item.unit_price);

        -- Existing inventory trigger deducts stock
        INSERT INTO public.inventory_transactions (
            product_id,
            transaction_type,
            quantity,
            notes
        )
        VALUES (
            v_item.product_id,
            'OUT',
            v_item.quantity,
            'Completed order #' || p_order_id
        );
    END LOOP;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION
            'Order % has no items', p_order_id;
    END IF;

    -- Complete order and save calculated total
    UPDATE public.orders
    SET
        total_amount = v_total,
        status = 'COMPLETED'
    WHERE order_id = p_order_id;

    RETURN v_total;
END;
$$;


ALTER FUNCTION public.complete_order(p_order_id integer) OWNER TO inventory_owner;

--
-- Name: create_pending_order(integer, text); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.create_pending_order(p_user_id integer, p_notes text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_order_id INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.users
        WHERE user_id = p_user_id
          AND role = 'PRODUCT_MANAGER'
          AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION
            'Active Product Manager required';
    END IF;

    INSERT INTO public.orders (
        created_by,
        status,
        total_amount,
        notes
    )
    VALUES (
        p_user_id,
        'PENDING',
        0,
        p_notes
    )
    RETURNING order_id INTO v_order_id;

    RETURN v_order_id;
END;
$$;


ALTER FUNCTION public.create_pending_order(p_user_id integer, p_notes text) OWNER TO inventory_owner;

--
-- Name: create_product(character varying, character varying, text, numeric, integer); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer DEFAULT 10) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_product_id INTEGER;
BEGIN
    IF NULLIF(BTRIM(p_name), '') IS NULL
       OR NULLIF(BTRIM(p_sku), '') IS NULL THEN
        RAISE EXCEPTION 'Product name and SKU are required';
    END IF;

    IF p_price IS NULL OR p_price < 0
       OR p_reorder_level IS NULL
       OR p_reorder_level < 0 THEN
        RAISE EXCEPTION 'Invalid price or reorder level';
    END IF;

    INSERT INTO public.products (
        product_name,
        sku,
        description,
        quantity,
        unit_price,
        reorder_level
    )
    VALUES (
        BTRIM(p_name),
        BTRIM(p_sku),
        p_description,
        0,
        p_price,
        p_reorder_level
    )
    RETURNING product_id INTO v_product_id;

    RETURN v_product_id;
END;
$$;


ALTER FUNCTION public.create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer) OWNER TO inventory_owner;

--
-- Name: protect_inventory_history(); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.protect_inventory_history() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION
        'Inventory transactions cannot be updated or deleted. Record a correcting transaction instead.';
END;
$$;


ALTER FUNCTION public.protect_inventory_history() OWNER TO inventory_owner;

--
-- Name: protect_order_items(); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.protect_order_items() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_order_id INTEGER;
    v_status VARCHAR(20);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.order_id <> OLD.order_id THEN
            RAISE EXCEPTION
                'Moving items between orders is not allowed';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    SELECT status
    INTO v_status
    FROM public.orders
    WHERE order_id = v_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Order % does not exist', v_order_id;
    END IF;

    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Cannot modify items of finalized order %',
            v_order_id;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.protect_order_items() OWNER TO inventory_owner;

--
-- Name: protect_order_records(); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.protect_order_records() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Orders cannot be deleted. Use cancellation instead.';
    END IF;

    IF OLD.status <> 'PENDING' THEN
        RAISE EXCEPTION
            'Finalized order % cannot be modified',
            OLD.order_id;
    END IF;

    IF NEW.order_id IS DISTINCT FROM OLD.order_id
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.order_date IS DISTINCT FROM OLD.order_date
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION
            'Order identity and ownership cannot be changed';
    END IF;

    IF NEW.status NOT IN (
        'PENDING', 'COMPLETED', 'CANCELLED'
    ) THEN
        RAISE EXCEPTION 'Invalid order status';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.protect_order_records() OWNER TO inventory_owner;

--
-- Name: record_stock_transaction(integer, character varying, integer, text); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
    v_transaction_id INTEGER;
BEGIN
    INSERT INTO inventory_transactions (
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


ALTER FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text) OWNER TO inventory_owner;

--
-- Name: update_inventory_quantity(); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.update_inventory_quantity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.transaction_type = 'IN' THEN
        UPDATE products
        SET quantity = quantity + NEW.quantity
        WHERE product_id = NEW.product_id;

    ELSIF NEW.transaction_type = 'OUT' THEN
        UPDATE products
        SET quantity = quantity - NEW.quantity
        WHERE product_id = NEW.product_id
          AND quantity >= NEW.quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Insufficient stock for product ID %',
                NEW.product_id;
        END IF;

    ELSIF NEW.transaction_type = 'ADJUSTMENT' THEN
        UPDATE products
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


ALTER FUNCTION public.update_inventory_quantity() OWNER TO inventory_owner;

--
-- Name: update_product_details(integer, character varying, text, numeric, integer); Type: FUNCTION; Schema: public; Owner: inventory_owner
--

CREATE FUNCTION public.update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
    IF NULLIF(BTRIM(p_name), '') IS NULL
       OR p_price IS NULL OR p_price < 0
       OR p_reorder_level IS NULL
       OR p_reorder_level < 0 THEN
        RAISE EXCEPTION 'Invalid product details';
    END IF;

    UPDATE public.products
    SET product_name = BTRIM(p_name),
        description = p_description,
        unit_price = p_price,
        reorder_level = p_reorder_level
    WHERE product_id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Product % not found', p_product_id;
    END IF;
END;
$$;


ALTER FUNCTION public.update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer) OWNER TO inventory_owner;

SET default_table_access_method = heap;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.orders (
    order_id integer NOT NULL,
    created_by integer NOT NULL,
    order_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_amount numeric(12,2) DEFAULT 0.00 NOT NULL,
    status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL,
    notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_order_status CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'COMPLETED'::character varying, 'CANCELLED'::character varying])::text[]))),
    CONSTRAINT chk_order_total CHECK ((total_amount >= (0)::numeric))
);


ALTER TABLE public.orders OWNER TO inventory_owner;

--
-- Name: users; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role character varying(30) NOT NULL,
    first_name character varying(50),
    last_name character varying(50),
    email character varying(100),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT chk_password_hash_not_blank CHECK ((length(TRIM(BOTH FROM password_hash)) > 0)),
    CONSTRAINT chk_user_role CHECK (((role)::text = ANY ((ARRAY['SUPER_USER'::character varying, 'INVENTORY_MANAGER'::character varying, 'PRODUCT_MANAGER'::character varying])::text[]))),
    CONSTRAINT chk_username_not_blank CHECK ((length(TRIM(BOTH FROM username)) > 0))
);


ALTER TABLE public.users OWNER TO inventory_owner;

--
-- Name: employee_order_summary; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.employee_order_summary AS
 SELECT u.user_id,
    u.username,
    u.role,
    count(o.order_id) AS total_orders,
    count(o.order_id) FILTER (WHERE ((o.status)::text = 'COMPLETED'::text)) AS completed_orders,
    count(o.order_id) FILTER (WHERE ((o.status)::text = 'PENDING'::text)) AS pending_orders,
    COALESCE(sum(o.total_amount) FILTER (WHERE ((o.status)::text = 'COMPLETED'::text)), (0)::numeric) AS completed_order_value
   FROM (public.users u
     LEFT JOIN public.orders o ON ((u.user_id = o.created_by)))
  GROUP BY u.user_id, u.username, u.role;


ALTER VIEW public.employee_order_summary OWNER TO inventory_owner;

--
-- Name: products; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.products (
    product_id integer NOT NULL,
    product_name character varying(100) NOT NULL,
    description text,
    sku character varying(50) NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    reorder_level integer DEFAULT 10 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    supplier_id integer,
    CONSTRAINT chk_quantity CHECK ((quantity >= 0)),
    CONSTRAINT chk_reorder_level CHECK ((reorder_level >= 0)),
    CONSTRAINT chk_unit_price CHECK ((unit_price >= (0)::numeric))
);


ALTER TABLE public.products OWNER TO inventory_owner;

--
-- Name: inventory_summary; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.inventory_summary AS
 SELECT count(*) AS total_products,
    COALESCE(sum(quantity), (0)::bigint) AS total_stock_quantity,
    COALESCE(sum(((quantity)::numeric * unit_price)), (0)::numeric) AS total_inventory_value,
    count(*) FILTER (WHERE ((quantity > 0) AND (quantity <= reorder_level))) AS low_stock_products,
    count(*) FILTER (WHERE (quantity = 0)) AS out_of_stock_products,
    count(*) FILTER (WHERE (quantity > reorder_level)) AS healthy_stock_products
   FROM public.products;


ALTER VIEW public.inventory_summary OWNER TO inventory_owner;

--
-- Name: inventory_transactions; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.inventory_transactions (
    transaction_id integer NOT NULL,
    product_id integer NOT NULL,
    transaction_type character varying(20) NOT NULL,
    quantity integer NOT NULL,
    transaction_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    notes text,
    CONSTRAINT chk_transaction_quantity CHECK (((((transaction_type)::text = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying])::text[])) AND (quantity > 0)) OR (((transaction_type)::text = 'ADJUSTMENT'::text) AND (quantity >= 0)))),
    CONSTRAINT chk_transaction_type CHECK (((transaction_type)::text = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying, 'ADJUSTMENT'::character varying])::text[])))
);


ALTER TABLE public.inventory_transactions OWNER TO inventory_owner;

--
-- Name: inventory_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.inventory_transactions ALTER COLUMN transaction_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.inventory_transactions_transaction_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.suppliers (
    supplier_id integer NOT NULL,
    supplier_name character varying(100) NOT NULL,
    contact_person character varying(100),
    email character varying(100),
    phone character varying(20),
    address text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.suppliers OWNER TO inventory_owner;

--
-- Name: inventory_value_report; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.inventory_value_report AS
 SELECT p.product_id,
    p.product_name,
    p.sku,
    p.quantity,
    p.unit_price,
    ((p.quantity)::numeric * p.unit_price) AS total_product_value,
    p.reorder_level,
    s.supplier_name,
        CASE
            WHEN (p.quantity = 0) THEN 'OUT OF STOCK'::text
            WHEN (p.quantity <= p.reorder_level) THEN 'LOW STOCK'::text
            ELSE 'IN STOCK'::text
        END AS stock_status
   FROM (public.products p
     LEFT JOIN public.suppliers s ON ((p.supplier_id = s.supplier_id)));


ALTER VIEW public.inventory_value_report OWNER TO inventory_owner;

--
-- Name: low_stock_report; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.low_stock_report AS
 SELECT p.product_id,
    p.product_name,
    p.sku,
    p.quantity,
    p.reorder_level,
    s.supplier_name,
        CASE
            WHEN (p.quantity = 0) THEN 'OUT OF STOCK'::text
            WHEN (p.quantity <= p.reorder_level) THEN 'LOW STOCK'::text
            ELSE 'IN STOCK'::text
        END AS stock_status
   FROM (public.products p
     LEFT JOIN public.suppliers s ON ((p.supplier_id = s.supplier_id)))
  WHERE (p.quantity <= p.reorder_level);


ALTER VIEW public.low_stock_report OWNER TO inventory_owner;

--
-- Name: order_items; Type: TABLE; Schema: public; Owner: inventory_owner
--

CREATE TABLE public.order_items (
    order_item_id integer NOT NULL,
    order_id integer NOT NULL,
    product_id integer NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    CONSTRAINT chk_order_item_price CHECK ((unit_price >= (0)::numeric)),
    CONSTRAINT chk_order_item_quantity CHECK ((quantity > 0))
);


ALTER TABLE public.order_items OWNER TO inventory_owner;

--
-- Name: order_history; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.order_history AS
 SELECT o.order_id,
    o.order_date,
    u.username AS created_by,
    o.status,
    count(oi.order_item_id) AS total_line_items,
    COALESCE(sum(oi.quantity), (0)::bigint) AS total_units,
    o.total_amount,
    o.notes
   FROM ((public.orders o
     JOIN public.users u ON ((o.created_by = u.user_id)))
     LEFT JOIN public.order_items oi ON ((o.order_id = oi.order_id)))
  GROUP BY o.order_id, o.order_date, u.username, o.status, o.total_amount, o.notes;


ALTER VIEW public.order_history OWNER TO inventory_owner;

--
-- Name: order_items_order_item_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.order_items ALTER COLUMN order_item_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.order_items_order_item_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: order_receipt; Type: VIEW; Schema: public; Owner: inventory_owner
--

CREATE VIEW public.order_receipt AS
 SELECT o.order_id,
    o.order_date,
    o.status,
    u.username AS created_by,
    oi.order_item_id,
    p.product_id,
    p.product_name,
    p.sku,
    oi.quantity,
    oi.unit_price,
    ((oi.quantity)::numeric * oi.unit_price) AS line_total,
    o.total_amount AS order_total
   FROM (((public.orders o
     JOIN public.users u ON ((o.created_by = u.user_id)))
     JOIN public.order_items oi ON ((o.order_id = oi.order_id)))
     JOIN public.products p ON ((oi.product_id = p.product_id)))
  WHERE ((o.status)::text = 'COMPLETED'::text);


ALTER VIEW public.order_receipt OWNER TO inventory_owner;

--
-- Name: orders_order_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.orders ALTER COLUMN order_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.orders_order_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: products_product_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.products ALTER COLUMN product_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.products_product_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.suppliers ALTER COLUMN supplier_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.suppliers_supplier_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: inventory_owner
--

ALTER TABLE public.users ALTER COLUMN user_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_user_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: inventory_transactions inventory_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_pkey PRIMARY KEY (transaction_id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_item_id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: products products_sku_key; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);


--
-- Name: suppliers suppliers_email_key; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_email_key UNIQUE (email);


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (supplier_id);


--
-- Name: order_items uq_order_product; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT uq_order_product UNIQUE (order_id, product_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: inventory_transactions trg_protect_inventory; Type: TRIGGER; Schema: public; Owner: inventory_owner
--

CREATE TRIGGER trg_protect_inventory BEFORE DELETE OR UPDATE ON public.inventory_transactions FOR EACH ROW EXECUTE FUNCTION public.protect_inventory_history();


--
-- Name: order_items trg_protect_order_items; Type: TRIGGER; Schema: public; Owner: inventory_owner
--

CREATE TRIGGER trg_protect_order_items BEFORE INSERT OR DELETE OR UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION public.protect_order_items();


--
-- Name: orders trg_protect_orders; Type: TRIGGER; Schema: public; Owner: inventory_owner
--

CREATE TRIGGER trg_protect_orders BEFORE DELETE OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.protect_order_records();


--
-- Name: inventory_transactions trg_update_inventory; Type: TRIGGER; Schema: public; Owner: inventory_owner
--

CREATE TRIGGER trg_update_inventory BEFORE INSERT ON public.inventory_transactions FOR EACH ROW EXECUTE FUNCTION public.update_inventory_quantity();


--
-- Name: order_items fk_order_items_order; Type: FK CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_order_items_order FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE RESTRICT;


--
-- Name: order_items fk_order_items_product; Type: FK CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_order_items_product FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE RESTRICT;


--
-- Name: orders fk_orders_user; Type: FK CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_orders_user FOREIGN KEY (created_by) REFERENCES public.users(user_id) ON DELETE RESTRICT;


--
-- Name: products fk_products_supplier; Type: FK CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_products_supplier FOREIGN KEY (supplier_id) REFERENCES public.suppliers(supplier_id);


--
-- Name: inventory_transactions fk_transaction_product; Type: FK CONSTRAINT; Schema: public; Owner: inventory_owner
--

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT fk_transaction_product FOREIGN KEY (product_id) REFERENCES public.products(product_id);
