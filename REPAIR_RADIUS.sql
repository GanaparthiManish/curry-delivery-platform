-- ==========================================
-- 🚀 RADIUS REPAIR V61.0
-- ==========================================
-- 🎯 MISSION: Fix the RESTRICTED_RADIUS error blocking orders at 12.24km.

BEGIN;

-- Increase radius for all vendors to 50km
UPDATE public.vendors SET delivery_radius_km = 50.0 WHERE delivery_radius_km < 50.0 OR delivery_radius_km IS NULL;

-- Update the enforcement trigger to be more permissive (50km limit)
CREATE OR REPLACE FUNCTION public.trg_enforce_distance_snapshot()
RETURNS TRIGGER AS $$
DECLARE
    v_vlat DOUBLE PRECISION;
    v_vlng DOUBLE PRECISION;
    v_vrad DOUBLE PRECISION := 50.0; -- Default to 50km
    v_dist DOUBLE PRECISION;
BEGIN
    -- Get vendor data
    SELECT latitude, longitude, COALESCE(delivery_radius_km, 50.0)
    INTO v_vlat, v_vlng, v_vrad
    FROM vendors WHERE id::text = NEW.vendor_id::text;

    -- Check Coords
    IF v_vlat IS NOT NULL AND NEW.delivery_lat IS NOT NULL THEN
        v_dist := public.calculate_distance_km(NEW.delivery_lat, NEW.delivery_lng, v_vlat, v_vlng);
        -- Allow up to v_vrad or a global 50km safety net
        IF v_dist > GREATEST(v_vrad, 50.0) THEN
            RAISE EXCEPTION 'RESTRICTED_RADIUS: Delivery address too far (%km). Max allowed is %km.', 
                ROUND(v_dist::numeric, 2), GREATEST(v_vrad, 50.0);
        END IF;
    END IF;

    -- Populate SNAPSHOT fields if missing
    IF NEW.delivery_address_text IS NULL THEN
        NEW.delivery_address_text := NEW.delivery_address;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Also fix the place_order_v20/v21/v22 functions to use 50km
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

    SELECT latitude, longitude, COALESCE(delivery_radius_km, 50.0)
    INTO v_vlat, v_vlng, v_vrad
    FROM public.vendors WHERE id = v_vendor_id;

    v_dist := public.calculate_distance_km(v_lat, v_lng, v_vlat, v_vlng);
    
    IF v_dist > GREATEST(v_vrad, 50.0) THEN
        RAISE EXCEPTION 'OUT_OF_RADIUS: Selected address is %km away. Max allowed is %km.', 
            ROUND(v_dist::numeric, 2), GREATEST(v_vrad, 50.0);
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

COMMIT;
NOTIFY pgrst, 'reload schema';
