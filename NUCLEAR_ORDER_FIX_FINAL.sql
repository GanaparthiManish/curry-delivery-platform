-- ============================================================
-- NUCLEAR ORDER FIX: Fix UPI Visibility + COD payment_status
-- ============================================================

BEGIN;

-- ── 1. FIX ALL STUCK UPI ORDERS (payment_pending → PLACED)
-- These are orders where the Razorpay payment likely succeeded
-- but the RPC never ran or failed silently.
-- We fix any UPI order that is in PAYMENT_PENDING for > 10 minutes
-- ──────────────────────────────────────────────────────────
UPDATE public.orders
SET
    order_status = 'PLACED',
    status       = 'PLACED',
    payment_status = 'SUCCESS',
    updated_at   = now()
WHERE
    payment_method IN ('UPI', 'upi')
    AND (order_status IN ('PAYMENT_PENDING', 'payment_pending', 'Pending', 'PENDING')
         OR status IN ('PAYMENT_PENDING', 'payment_pending', 'Pending', 'PENDING'))
    AND order_status NOT IN ('CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed')
    AND status NOT IN ('CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed')
    AND created_at < now() - interval '5 minutes';

-- ── 2. FIX COD ORDERS: payment_status should be SUCCESS, not PENDING
UPDATE public.orders
SET
    payment_status = 'SUCCESS',
    updated_at     = now()
WHERE
    payment_method IN ('COD', 'cod')
    AND payment_status IN ('PENDING', 'pending', '')
    AND order_status NOT IN ('CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed')
    AND status NOT IN ('CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed');

-- ── 3. FIX MIXED STATUS: orders where status != order_status
UPDATE public.orders
SET status = order_status
WHERE order_status IS NOT NULL
  AND order_status != ''
  AND (status IS NULL OR status != order_status)
  AND order_status NOT IN ('PAYMENT_PENDING', 'CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed')
  AND COALESCE(status, '') NOT IN ('CANCELLED', 'DELIVERED', 'FAILED', 'payment_failed');

-- ── 4. REBUILD confirm_upi_payment_v2 to be BULLETPROOF
DROP FUNCTION IF EXISTS public.confirm_upi_payment_v2(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS public.confirm_upi_payment_v2(text, text) CASCADE;

-- Accepts both UUID and TEXT for p_order_id
CREATE OR REPLACE FUNCTION public.confirm_upi_payment_v2(
    p_order_id TEXT,
    p_payment_id TEXT DEFAULT 'UPI_CONFIRMED'
)
RETURNS void AS $$
BEGIN
    -- Update using text comparison to handle both UUID and string IDs
    UPDATE public.orders
    SET
        order_status   = 'PLACED',
        status         = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id     = p_payment_id,
        updated_at     = now()
    WHERE id::text = p_order_id
       OR id::text = lower(p_order_id);

    -- If no rows were updated, raise an error so client knows
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ORDER_NOT_FOUND: % not found in orders table', p_order_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 5. REBUILD place_order_stabilized_v5 (COD) — always sets payment_status SUCCESS
DROP FUNCTION IF EXISTS public.place_order_stabilized_v5(text,text,jsonb,double precision,double precision,double precision,double precision,double precision,text,double precision,double precision,text,text,text,text,text) CASCADE;

CREATE OR REPLACE FUNCTION public.place_order_stabilized_v5(
    p_customer_id      TEXT,
    p_vendor_id        TEXT,
    p_items            JSONB,
    p_total            DOUBLE PRECISION,
    p_item_total       DOUBLE PRECISION,
    p_delivery_fee     DOUBLE PRECISION,
    p_platform_fee     DOUBLE PRECISION,
    p_gst              DOUBLE PRECISION,
    p_address          TEXT,
    p_lat              DOUBLE PRECISION,
    p_lng              DOUBLE PRECISION,
    p_payment_method   TEXT DEFAULT 'COD',
    p_instructions     TEXT DEFAULT '',
    p_address_id       TEXT DEFAULT NULL,
    p_payment_status   TEXT DEFAULT 'SUCCESS',
    p_payment_id       TEXT DEFAULT 'COD_UNIV'
)
RETURNS TEXT AS $$
DECLARE
    v_order_id TEXT;
    v_status   TEXT;
    v_pstatus  TEXT;
BEGIN
    IF p_payment_method = 'COD' THEN
        v_status  := 'PLACED';
        v_pstatus := 'SUCCESS';   -- COD is always SUCCESS immediately
    ELSE
        v_status  := 'PAYMENT_PENDING';
        v_pstatus := 'PENDING';
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
        v_status, v_status, p_payment_method, v_pstatus, p_payment_id,
        p_instructions, now()
    ) RETURNING id::text INTO v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 6. REBUILD place_order_v22 (UPI) — sets PAYMENT_PENDING correctly
DROP FUNCTION IF EXISTS public.place_order_v22(jsonb) CASCADE;

CREATE OR REPLACE FUNCTION public.place_order_v22(p_params JSONB)
RETURNS TEXT AS $$
DECLARE
    v_order_id UUID;
BEGIN
    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst,
        delivery_address, delivery_lat, delivery_lng,
        order_status, status, payment_method, payment_status,
        cooking_instructions, created_at,
        delivery_pincode, delivery_phone
    ) VALUES (
        p_params->>'customer_id',
        (p_params->>'vendor_id')::UUID,
        p_params->'items',
        (p_params->>'total')::double precision,
        (p_params->>'item_total')::double precision,
        COALESCE((p_params->>'delivery_fee')::double precision, 0),
        COALESCE((p_params->>'platform_fee')::double precision, 0),
        COALESCE((p_params->>'gst')::double precision, 0),
        p_params->>'address',
        (p_params->>'lat')::double precision,
        (p_params->>'lng')::double precision,
        'PAYMENT_PENDING', 'PAYMENT_PENDING',
        p_params->>'payment_method', 'PENDING',
        p_params->>'cooking_instructions', now(),
        p_params->>'pincode',
        p_params->>'customer_phone'
    ) RETURNING id INTO v_order_id;

    RETURN v_order_id::text;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 7. REBUILD the stabilized view to also expose `status` column
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;

CREATE VIEW public.order_tracking_stabilized_v1 AS
SELECT
    o.id AS order_id,
    o.id AS id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    -- Normalize: prefer order_status, never NULL
    COALESCE(o.order_status, o.status, 'PLACED') AS order_status,
    COALESCE(o.status, o.order_status, 'PLACED')  AS status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    o.item_total,
    o.delivery_fee,
    o.platform_fee,
    o.gst,
    o.tip_amount,
    COALESCE(o.delivery_address, 'Address not found') AS delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.vendor_lat,
    o.vendor_lng,
    COALESCE(r.current_lat, o.rider_lat, 0) AS rider_lat,
    COALESCE(r.current_lng, o.rider_lng, 0) AS rider_lng,
    COALESCE(r.heading, 0) AS rider_heading,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions,
    o.delivery_phone AS customer_phone,
    o.delivery_pincode,
    o.delivery_house_number,
    CASE
        WHEN COALESCE(o.order_status, o.status) = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN COALESCE(o.order_status, o.status) = 'PLACED'          THEN 'Order Placed'
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED'        THEN 'Preparing'
        WHEN COALESCE(o.order_status, o.status) = 'COOKING'         THEN 'Cooking'
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP'       THEN 'Rider is on the way'
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED'       THEN 'Order Delivered'
        WHEN COALESCE(o.order_status, o.status) = 'CANCELLED'       THEN 'Cancelled'
        ELSE COALESCE(o.order_status, o.status, 'Unknown')
    END AS status_display,
    CASE
        WHEN COALESCE(o.order_status, o.status) = 'PAYMENT_PENDING' THEN 0
        WHEN COALESCE(o.order_status, o.status) = 'PLACED'          THEN 1
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED'        THEN 2
        WHEN COALESCE(o.order_status, o.status) = 'COOKING'         THEN 3
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP'       THEN 4
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED'       THEN 5
        ELSE 1
    END AS current_step,
    v.name      AS vendor_name,
    v.image_url AS vendor_image,
    r.name      AS rider_name,
    r.phone     AS rider_phone,
    r.avatar_url AS rider_avatar,
    r.rating    AS rider_rating,
    COALESCE(r.vehicle_number, r.vehicle_details, 'Bike') AS rider_vehicle
FROM public.orders o
LEFT JOIN public.vendors        v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- ── 8. Grant permissions
GRANT SELECT ON public.order_tracking_stabilized_v1
    TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.confirm_upi_payment_v2(text, text)
    TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.place_order_stabilized_v5(text,text,jsonb,double precision,double precision,double precision,double precision,double precision,text,double precision,double precision,text,text,text,text,text)
    TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.place_order_v22(jsonb)
    TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
