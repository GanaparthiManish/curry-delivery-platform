-- ==========================================
-- 🚀 NUCLEAR RADIUS UNLOCK V60.0
-- ==========================================
-- 🎯 MISSION: Remove all distance blocks and set massive defaults (100km+).
-- 🛠️ STRATEGY: Update all radius triggers and functions to be extremely permissive.

BEGIN;

-- [1] Update all existing vendors to have a 100km radius
UPDATE public.vendors SET delivery_radius_km = 100 WHERE delivery_radius_km < 100 OR delivery_radius_km IS NULL;

-- [2] PATCH DISTANCE CALCULATION (Optional, but good to ensure consistency)
-- No changes needed to calculate_distance_km itself.

-- [3] PATCH NEARBY VENDORS RPC (v20 -> v21)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v20(p_params JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_lat DOUBLE PRECISION;
    v_lng DOUBLE PRECISION;
    v_max_radius DOUBLE PRECISION := 100.0; -- Increased to 100km
BEGIN
    v_lat := (p_params->>'lat')::DOUBLE PRECISION;
    v_lng := (p_params->>'lng')::DOUBLE PRECISION;

    RETURN (
        SELECT COALESCE(jsonb_agg(v_row), '[]'::jsonb)
        FROM (
            SELECT 
                v.*,
                public.calculate_distance_km(v_lat, v_lng, v.latitude, v.longitude) AS distance_km
            FROM public.vendors v
            WHERE 
                v.is_verified = TRUE
                AND v.is_active = TRUE
                AND v.status = 'ONLINE'
                AND v.latitude IS NOT NULL 
                AND v.longitude IS NOT NULL
                -- Removed is_open check here if we want them to see closed shops or handle it in UI
                AND public.calculate_distance_km(v_lat, v_lng, v.latitude, v.longitude) <= COALESCE(v.delivery_radius_km, v_max_radius)
            ORDER BY distance_km ASC
        ) v_row
    );
END;
$$;

-- [4] PATCH ORDER PLACEMENT RPC
CREATE OR REPLACE FUNCTION public.place_order_v20(p_params JSONB)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order_id UUID;
    v_customer_id TEXT;
    v_vendor_id UUID;
    v_lat DOUBLE PRECISION;
    v_lng DOUBLE PRECISION;
    v_total DOUBLE PRECISION;
    v_vlat DOUBLE PRECISION;
    v_vlng DOUBLE PRECISION;
    v_vrad DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
BEGIN
    v_customer_id := p_params->>'customer_id';
    v_vendor_id := (p_params->>'vendor_id')::UUID;
    v_lat := (p_params->>'lat')::DOUBLE PRECISION;
    v_lng := (p_params->>'lng')::DOUBLE PRECISION;
    v_total := (p_params->>'total')::DOUBLE PRECISION;

    SELECT latitude, longitude, COALESCE(delivery_radius_km, 100.0)
    INTO v_vlat, v_vlng, v_vrad
    FROM public.vendors WHERE id = v_vendor_id;

    v_dist := public.calculate_distance_km(v_lat, v_lng, v_vlat, v_vlng);
    
    -- Extremely permissive check
    IF v_dist > v_vrad AND v_dist > 100.0 THEN
        RAISE EXCEPTION 'OUT_OF_RADIUS: Selected address is %km away. Even the nuclear 100km limit is exceeded.', 
            ROUND(v_dist::numeric, 2);
    END IF;

    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, status, payment_method,
        delivery_address, delivery_address_text, delivery_pincode, delivery_phone,
        delivery_lat, delivery_lng, created_at
    ) VALUES (
        v_customer_id, v_vendor_id, p_params->'items', v_total,
        CASE WHEN p_params->>'payment_method' = 'UPI' THEN 'PAYMENT_PENDING' ELSE 'PLACED' END,
        p_params->>'payment_method',
        p_params->>'address', p_params->>'address', p_params->>'pincode', p_params->>'customer_phone',
        v_lat, v_lng, now()
    ) RETURNING id INTO v_order_id;

    RETURN v_order_id;
END;
$$;

-- [5] PATCH THE RESTRICTED_RADIUS TRIGGER
CREATE OR REPLACE FUNCTION public.trg_enforce_distance_snapshot()
RETURNS TRIGGER AS $$
DECLARE
    v_vlat DOUBLE PRECISION;
    v_vlng DOUBLE PRECISION;
    v_vrad DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
BEGIN
    SELECT latitude, longitude, COALESCE(delivery_radius_km, 100.0)
    INTO v_vlat, v_vlng, v_vrad
    FROM vendors WHERE id::text = NEW.vendor_id::text;

    IF v_vlat IS NOT NULL AND NEW.delivery_lat IS NOT NULL THEN
        v_dist := public.calculate_distance_km(NEW.delivery_lat, NEW.delivery_lng, v_vlat, v_vlng);
        -- Permissive: Only block if over 100km
        IF v_dist > v_vrad AND v_dist > 100.0 THEN
            RAISE EXCEPTION 'RESTRICTED_RADIUS: Delivery address too far (%km). Max allowed is 100km.', ROUND(v_dist::numeric, 2);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- [6] PATCH OTHER RADIUS TRIGGERS
CREATE OR REPLACE FUNCTION public.enforce_order_delivery_radius()
RETURNS TRIGGER AS $$
DECLARE
    v_vrad NUMERIC := 100.0;
    v_dist DOUBLE PRECISION;
BEGIN
    -- Just bypass or use 100km
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
NOTIFY pgrst, 'reload schema';
