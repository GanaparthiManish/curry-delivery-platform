-- 🛡️ ULTIMATE STABILITY & NOTIFICATION REPAIR (V51.0)
-- 🎯 MISSION: STRICT 5KM RADIUS ENFORCEMENT ON ALL ORDERS + NOTIFICATIONS
-- 🎯 REASON: Prevent 17km orders, enforce 5km limit on Map & Checkout.

BEGIN;

-- 🧹 CLEANUP OLD VERSIONS (Avoid 42P13 errors)
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.place_order_v22(JSONB);
DROP FUNCTION IF EXISTS public.place_order_stabilized_v5(text,text,jsonb,double precision,double precision,double precision,double precision,double precision,text,double precision,double precision,text,text,text,text,text);

-- 1. 🥘 get_nearby_vendors_v24 (STRICT 5KM FOR MAP)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(v_data)
        FROM (
            SELECT 
                v.*,
                (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
                ))))::double precision as distance_km
            FROM public.vendors v
            WHERE v.status = 'ONLINE'
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= 5.0 -- 🌍 STRICT 5KM RADIUS RE-ENFORCED
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. 🛡️ place_order_v22 (WITH DISTANCE VALIDATION)
CREATE OR REPLACE FUNCTION public.place_order_v22(p_params JSONB)
RETURNS TEXT AS $$
DECLARE
    v_order_id UUID;
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
BEGIN
    -- Get Vendor Location
    SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng 
    FROM public.vendors WHERE id::text = p_params->>'vendor_id';

    -- Calculate Distance
    v_dist := (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians((p_params->>'lat')::double precision)) * cos(radians(v_vendor_lat)) * cos(radians(v_vendor_lng) - radians((p_params->>'lng')::double precision)) + 
                sin(radians((p_params->>'lat')::double precision)) * sin(radians(v_vendor_lat))
              ))));

    -- 🛑 BLOCK IF > 5KM
    IF v_dist > 5.0 THEN
        RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Distance % km exceeds 5km limit.', v_dist;
    END IF;

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
        0.0, -- 💰 NO EXTRA DELIVERY CHARGE AS REQUESTED
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

-- 3. 🛡️ place_order_stabilized_v5 (COD WITH DISTANCE VALIDATION)
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
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
BEGIN
    -- Get Vendor Location
    SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng 
    FROM public.vendors WHERE id::text = p_vendor_id;

    -- Calculate Distance
    v_dist := (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v_vendor_lat)) * cos(radians(v_vendor_lng) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v_vendor_lat))
              ))));

    -- 🛑 BLOCK IF > 5KM
    IF v_dist > 5.0 THEN
        RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Distance % km exceeds 5km limit.', v_dist;
    END IF;

    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst,
        delivery_address, delivery_lat, delivery_lng,
        order_status, status, payment_method, payment_status, payment_id,
        cooking_instructions, created_at
    ) VALUES (
        p_customer_id, p_vendor_id, p_items, p_total, p_item_total,
        0.0, -- 💰 NO EXTRA DELIVERY CHARGE AS REQUESTED
        p_platform_fee, p_gst,
        p_address, p_lat, p_lng,
        'PLACED', 'PLACED', p_payment_method, 'SUCCESS', p_payment_id,
        p_instructions, now()
    ) RETURNING id::text INTO v_order_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 🥘 Compatibility Overloads
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v23(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION DEFAULT 5.0
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_nearby_vendors_v24(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;

-- Permissions
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.place_order_v22(JSONB) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.place_order_stabilized_v5(text,text,jsonb,double precision,double precision,double precision,double precision,double precision,text,double precision,double precision,text,text,text,text,text) TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
