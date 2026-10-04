-- 🚀 PRODUCTION FINAL: EXTERMINATE PAYMENT_PENDING GHOSTS
-- MISSION: Ensure COD is PLACED immediately and UPI results in success or nothing.

BEGIN;

-- 1. FIX: place_order_stabilized_v5 (Used for COD)
CREATE OR REPLACE FUNCTION public.place_order_stabilized_v5(
    p_customer_id TEXT,
    p_vendor_id TEXT,
    p_items JSONB,
    p_total DOUBLE PRECISION,
    p_item_total DOUBLE PRECISION,
    p_delivery_fee DOUBLE PRECISION,
    p_platform_fee DOUBLE PRECISION,
    p_gst DOUBLE PRECISION,
    p_address TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '',
    p_address_id TEXT DEFAULT NULL,
    p_payment_status TEXT DEFAULT 'PENDING',
    p_payment_id TEXT DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_order_id TEXT;
    v_initial_status TEXT;
    v_final_payment_status TEXT;
BEGIN
    -- 🛡️ Logic: If COD, it's instantly PLACED and SUCCESS (for tracking purposes)
    IF p_payment_method = 'COD' THEN
        v_initial_status := 'PLACED';
        v_final_payment_status := 'SUCCESS';
    ELSE
        -- For UPI/Online, it stays PAYMENT_PENDING until verified
        v_initial_status := 'PAYMENT_PENDING';
        v_final_payment_status := p_payment_status;
    END IF;

    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst,
        delivery_address, delivery_lat, delivery_lng, 
        order_status, status, payment_method, payment_status, payment_id,
        cooking_instructions, created_at
    ) VALUES (
        p_customer_id, p_vendor_id, p_items, p_total, p_item_total,
        p_delivery_fee, p_platform_fee, p_gst,
        p_address, p_lat, p_lng,
        v_initial_status, v_initial_status, p_payment_method, v_final_payment_status, p_payment_id,
        p_instructions, now()
    ) RETURNING id::text INTO v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. FIX: confirm_upi_payment_v2 (Ensures state transitions correctly)
-- This function is called by the Customer App when Razorpay returns Success.
CREATE OR REPLACE FUNCTION confirm_upi_payment_v2(p_order_id uuid, p_payment_id text)
RETURNS void AS $$
BEGIN
    UPDATE public.orders
    SET 
        order_status = 'PLACED',
        status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = now()
    WHERE id = p_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. REFRESH SCHEMA
COMMIT;
NOTIFY pgrst, 'reload schema';
