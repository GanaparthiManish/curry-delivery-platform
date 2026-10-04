-- Run this in your Supabase SQL Editor to fix the "function name is not unique" error.

BEGIN;

-- 1. Drop ALL existing versions of place_order_v4
DO $$ 
DECLARE 
    r record;
BEGIN
    FOR r IN 
        SELECT oid::regprocedure AS procedure_name 
        FROM pg_proc 
        WHERE proname = 'place_order_v4' AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.procedure_name || ' CASCADE';
    END LOOP;
END $$;

-- 2. Recreate the correct single version of place_order_v4
CREATE OR REPLACE FUNCTION public.place_order_v4(
    p_customer_id TEXT,
    p_vendor_items JSONB, 
    p_address TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '',
    p_payment_status TEXT DEFAULT 'PENDING'
)
RETURNS TEXT AS $$
DECLARE
    v_master_id TEXT;
    v_sub_order JSONB;
BEGIN
    v_master_id := gen_random_uuid()::TEXT;

    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        INSERT INTO public.orders (
            id, master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions
        ) VALUES (
            gen_random_uuid()::TEXT,
            v_master_id,
            p_customer_id,
            (v_sub_order->>'vendor_id')::TEXT,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            'PLACED',
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.place_order_v4 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
