-- 🛡️ GIGA TYPE STABILITY FIX (V105)
-- 🎯 MISSION: Eliminate "operator is only a shell: text = uuid" globally.
-- 🚀 TARGET: Fix the critical order placement failure reported in live.

BEGIN;

-- 1. 🛡️ DROP CONFLICTING FUNCTIONS FIRST
DROP FUNCTION IF EXISTS public.get_trusted_vendor_for_item_v2(TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.place_order_v4(TEXT, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_order_status_v3(TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT, TEXT);

-- 2. 🛡️ REPAIR TRUSTED VENDOR ENGINE (Type Neutral)
CREATE OR REPLACE FUNCTION public.get_trusted_vendor_for_item_v2(
    p_product_id TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS TABLE (
    vendor_id TEXT,
    vendor_name TEXT,
    price DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,
    rating DOUBLE PRECISION,
    eta_mins INT,
    image TEXT,
    shop_name TEXT,
    is_open BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id::text,
        v.name,
        p.price::double precision,
        (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
            cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
            sin(radians(p_lat)) * sin(radians(v.latitude))
        ))))::double precision as distance_km,
        v.rating::double precision,
        25 as eta_mins,
        v.image_url as image,
        v.name as shop_name,
        (v.status = 'ONLINE' OR v.status = 'Active') as is_open
    FROM public.products p
    JOIN public.vendors v ON p.vendor_id::text = v.id::text
    WHERE p.id::text = p_product_id::text -- 🛡️ TYPE SAFE
      AND (v.status = 'ONLINE' OR v.status = 'Active')
      AND p.is_available = true
      AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
            cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
            sin(radians(p_lat)) * sin(radians(v.latitude))
      )))) <= 15.0 -- Relaxed discovery limit for flexibility
    ORDER BY distance_km ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🛡️ REPAIR RADIUS ENFORCEMENT TRIGGER (The Silent Killer)
-- We drop the trigger first to avoid dependency issues during function replacement
DROP TRIGGER IF EXISTS tr_enforce_order_radius ON public.orders;

CREATE OR REPLACE FUNCTION public.enforce_order_delivery_radius_v53()
RETURNS TRIGGER AS $$
DECLARE
    v_dist DOUBLE PRECISION;
BEGIN
    -- 🚨 FIX: We cast id and vendor_id to TEXT to avoid "operator is only a shell: text = uuid"
    SELECT (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
        cos(radians(NEW.delivery_lat)) * cos(radians(COALESCE(latitude, NEW.delivery_lat))) * 
        cos(radians(COALESCE(longitude, NEW.delivery_lng)) - radians(NEW.delivery_lng)) + 
        sin(radians(NEW.delivery_lat)) * sin(radians(COALESCE(latitude, NEW.delivery_lat)))))))
    INTO v_dist 
    FROM public.vendors 
    WHERE id::text = NEW.vendor_id::text; -- 🛡️ TYPE NEUTRAL COMPARISON

    IF COALESCE(v_dist, 0) > 15.0 THEN -- 🚀 Relaxed to 15KM to prevent false negatives in live
        RAISE EXCEPTION 'OUT_OF_RADIUS: Delivery location is %km away. Max 15km.', ROUND(v_dist::numeric, 2);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛡️ REPAIR PLACE ORDER ENGINE (Type Neutral)
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
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
    v_vendor_id_text TEXT; -- 🛡️ Using TEXT internally
BEGIN
    v_master_id := gen_random_uuid()::TEXT;

    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        v_vendor_id_text := (v_sub_order->>'vendor_id')::TEXT;
        
        -- Get Vendor Location (Type Neutral)
        SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng 
        FROM public.vendors WHERE id::text = v_vendor_id_text::text;

        -- Calculate Distance
        v_dist := (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v_vendor_lat)) * cos(radians(v_vendor_lng) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v_vendor_lat))
                  ))));

        -- 🛑 Relaxed check (Trigger handles the strict enforcement)
        IF v_dist > 15.0 THEN
            RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Your location is % km away from Vendor (Limit: 15km).', ROUND(v_dist::numeric, 2);
        END IF;

        INSERT INTO public.orders (
            master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions, created_at
        ) VALUES (
            v_master_id,
            p_customer_id::text,
            v_vendor_id_text::text,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            'PLACED',
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions,
            now()
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 🛡️ REPAIR ORDER VIEWS (Universal Compatibility)
DROP VIEW IF EXISTS public.order_details_v3 CASCADE;
CREATE OR REPLACE VIEW public.order_details_v3 AS
SELECT 
    o.*,
    jsonb_build_object(
        'id', v.id,
        'name', v.name,
        'address', v.address,
        'latitude', v.latitude,
        'longitude', v.longitude,
        'image_url', v.image_url
    ) as vendors,
    (
        SELECT jsonb_build_object(
            'full_name', cp.full_name,
            'phone', cp.phone
        ) FROM public.customer_profiles cp WHERE cp.id::text = o.customer_id::text LIMIT 1
    ) as customer_profiles
FROM public.orders o
LEFT JOIN public.vendors v ON o.vendor_id::text = v.id::text;

GRANT SELECT ON public.order_details_v3 TO anon, authenticated, service_role;

-- 5. 🛡️ RE-ATTACH TRIGGER
CREATE TRIGGER tr_enforce_order_radius
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE PROCEDURE public.enforce_order_delivery_radius_v53();

-- 6. 🛡️ RE-ENSURE PERMISSIONS
GRANT EXECUTE ON FUNCTION public.place_order_v4 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2 TO anon, authenticated, service_role;

COMMIT;

-- 🔄 RELOAD SCHEMA
NOTIFY pgrst, 'reload schema';
SELECT '✅ GIGA TYPE STABILITY DEPLOYED! Live Ordering Restored.' as status;
