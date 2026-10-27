-- Reviewed grants captured from the live database; no credentials.
-- Run only as part of setup for a dedicated new database.
-- Existing privileges outside these files are not a supported starting state.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO inventory_owner;
--
-- Dependencies: 5
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO inventory_admin;
GRANT USAGE ON SCHEMA public TO inventory_app;
GRANT USAGE ON SCHEMA public TO inventory_java;


--
-- Dependencies: 258
-- Name: FUNCTION add_order_item(p_order_id integer, p_product_id integer, p_quantity integer); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.add_order_item(p_order_id integer, p_product_id integer, p_quantity integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_order_item(p_order_id integer, p_product_id integer, p_quantity integer) TO inventory_app;


--
-- Dependencies: 253
-- Name: FUNCTION cancel_pending_order(p_order_id integer); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.cancel_pending_order(p_order_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_pending_order(p_order_id integer) TO inventory_app;


--
-- Dependencies: 255
-- Name: FUNCTION complete_order(p_order_id integer); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.complete_order(p_order_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.complete_order(p_order_id integer) TO inventory_app;
GRANT ALL ON FUNCTION public.complete_order(p_order_id integer) TO inventory_admin;


--
-- Dependencies: 257
-- Name: FUNCTION create_pending_order(p_user_id integer, p_notes text); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.create_pending_order(p_user_id integer, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_pending_order(p_user_id integer, p_notes text) TO inventory_app;


--
-- Dependencies: 251
-- Name: FUNCTION create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.create_product(p_name character varying, p_sku character varying, p_description text, p_price numeric, p_reorder_level integer) TO inventory_app;


--
-- Dependencies: 250
-- Name: FUNCTION protect_inventory_history(); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.protect_inventory_history() FROM PUBLIC;


--
-- Dependencies: 254
-- Name: FUNCTION protect_order_items(); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.protect_order_items() FROM PUBLIC;


--
-- Dependencies: 256
-- Name: FUNCTION protect_order_records(); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.protect_order_records() FROM PUBLIC;


--
-- Dependencies: 237
-- Name: FUNCTION record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text) TO inventory_app;
GRANT ALL ON FUNCTION public.record_stock_transaction(p_product_id integer, p_transaction_type character varying, p_quantity integer, p_notes text) TO inventory_admin;


--
-- Dependencies: 249
-- Name: FUNCTION update_inventory_quantity(); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.update_inventory_quantity() FROM PUBLIC;


--
-- Dependencies: 252
-- Name: FUNCTION update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer); Type: ACL; Schema: public; Owner: inventory_owner
--

REVOKE ALL ON FUNCTION public.update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_product_details(p_product_id integer, p_name character varying, p_description text, p_price numeric, p_reorder_level integer) TO inventory_app;


--
-- Dependencies: 231
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.orders TO inventory_app;


--
-- Dependencies: 229
-- Name: TABLE users; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.users TO inventory_java;


--
-- Dependencies: 236
-- Name: TABLE employee_order_summary; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.employee_order_summary TO inventory_app;
GRANT SELECT ON TABLE public.employee_order_summary TO inventory_admin;


--
-- Dependencies: 220
-- Name: TABLE products; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.products TO inventory_admin;
GRANT SELECT ON TABLE public.products TO inventory_app;


--
-- Dependencies: 226
-- Name: TABLE inventory_summary; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.inventory_summary TO inventory_app;
GRANT SELECT ON TABLE public.inventory_summary TO inventory_admin;


--
-- Dependencies: 224
-- Name: TABLE inventory_transactions; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.inventory_transactions TO inventory_admin;
GRANT SELECT ON TABLE public.inventory_transactions TO inventory_app;


--
-- Dependencies: 223
-- Name: SEQUENCE inventory_transactions_transaction_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.inventory_transactions_transaction_id_seq TO inventory_admin;
GRANT SELECT,USAGE ON SEQUENCE public.inventory_transactions_transaction_id_seq TO inventory_java;


--
-- Dependencies: 222
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.suppliers TO inventory_admin;
GRANT SELECT ON TABLE public.suppliers TO inventory_app;


--
-- Dependencies: 227
-- Name: TABLE inventory_value_report; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.inventory_value_report TO inventory_app;
GRANT SELECT ON TABLE public.inventory_value_report TO inventory_admin;


--
-- Dependencies: 225
-- Name: TABLE low_stock_report; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.low_stock_report TO inventory_app;
GRANT SELECT ON TABLE public.low_stock_report TO inventory_admin;


--
-- Dependencies: 233
-- Name: TABLE order_items; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.order_items TO inventory_app;


--
-- Dependencies: 235
-- Name: TABLE order_history; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.order_history TO inventory_app;
GRANT SELECT ON TABLE public.order_history TO inventory_admin;


--
-- Dependencies: 232
-- Name: SEQUENCE order_items_order_item_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.order_items_order_item_id_seq TO inventory_java;


--
-- Dependencies: 234
-- Name: TABLE order_receipt; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT ON TABLE public.order_receipt TO inventory_app;
GRANT SELECT ON TABLE public.order_receipt TO inventory_admin;


--
-- Dependencies: 230
-- Name: SEQUENCE orders_order_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.orders_order_id_seq TO inventory_java;


--
-- Dependencies: 219
-- Name: SEQUENCE products_product_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.products_product_id_seq TO inventory_admin;
GRANT SELECT,USAGE ON SEQUENCE public.products_product_id_seq TO inventory_java;


--
-- Dependencies: 221
-- Name: SEQUENCE suppliers_supplier_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.suppliers_supplier_id_seq TO inventory_admin;
GRANT SELECT,USAGE ON SEQUENCE public.suppliers_supplier_id_seq TO inventory_java;


--
-- Dependencies: 228
-- Name: SEQUENCE users_user_id_seq; Type: ACL; Schema: public; Owner: inventory_owner
--

GRANT SELECT,USAGE ON SEQUENCE public.users_user_id_seq TO inventory_java;



--
-- PostgreSQL database dump complete
--
