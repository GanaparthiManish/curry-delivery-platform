-- 📍 DYNAMIC LOGISTICS RADIUS ENFORCEMENT V2.1
-- 🎯 MISSION: Fix hardcoded 15km limits and synchronize with Admin Panel (system_config).

BEGIN;

-- 1. Create a Helper Function for RADIUS Retrieval
-- This function checks vendor-specific radius, then global system settings, then fallbacks.
CREATE OR REPLACE FUNCTION public.get_effective_delivery_radius(p_vendor_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_vendor_radius NUMERIC;
    v_system_radius NUMERIC;
    v_limit_radius NUMERIC;
BEGIN
    -- 1. Check Vendor Specific Override (Highest Priority)
    SELECT delivery_radius_km INTO v_vendor_radius 
    FROM public.vendors 
    WHERE id = p_vendor_id;

    IF v_vendor_radius IS NOT NULL AND v_vendor_radius > 0 THEN
        RETURN v_vendor_radius;
    END IF;

    -- 2. Check system_config (Command Center settings - 'deliveryRadius' field)
    -- As seen in DB: {"key":"system_config","value":{"deliveryRadius": 5.0, ...}}
    SELECT (value->>'deliveryRadius')::numeric INTO v_system_radius 
    FROM public.app_settings 
    WHERE key = 'system_config';

    IF v_system_radius IS NOT NULL AND v_system_radius > 0 THEN
        RETURN v_system_radius;
    END IF;

    -- 3. Check delivery_radius_limit (Legacy setting)
    -- As seen in DB: {"key":"delivery_radius_limit","value":15}
    -- Handle both object value and primitive value
    SELECT 
        CASE 
            WHEN jsonb_typeof(value) = 'object' THEN (value->>'km')::numeric
            WHEN jsonb_typeof(value) = 'number' THEN value::numeric
            ELSE NULL 
        END INTO v_limit_radius
    FROM public.app_settings 
    WHERE key = 'delivery_radius_limit';

    IF v_limit_radius IS NOT NULL AND v_limit_radius > 0 THEN
        RETURN v_limit_radius;
    END IF;

    -- 4. Ultimate Fallback (Match user's latest request)
    RETURN 5.0;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. UPDATE get_nearby_vendors_v23 to be DYNAMIC
-- Removed hardcoded 15.0 and replaced with get_effective_delivery_radius(v.id)
CREATE OR REPLACE FUNCTION get_nearby_vendors_v23(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS TABLE (
    id UUID,
    name TEXT,
    cuisine_type TEXT,
    rating NUMERIC,
    banner_url TEXT,
    logo_url TEXT,
    address TEXT,
    distance_km DOUBLE PRECISION,
    delivery_time TEXT,
    is_pure_veg BOOLEAN,
    has_offers BOOLEAN,
    price_for_two NUMERIC,
    status TEXT,
    is_open BOOLEAN,
    open_time TEXT,
    close_time TEXT,
    is_busy BOOLEAN,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id::UUID,
        v.name::TEXT,
        v.cuisine_type::TEXT,
        COALESCE(v.rating, 0)::NUMERIC,
        v.banner_url::TEXT,
        v.logo_url::TEXT,
        COALESCE(v.address, '')::TEXT,
        (6371 * acos(
            LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(COALESCE(v.latitude, p_lat))) * 
                cos(radians(COALESCE(v.longitude, p_lng)) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(COALESCE(v.latitude, p_lat)))
            ))
        ))::DOUBLE PRECISION AS d_km,
        v.delivery_time::TEXT,
        COALESCE(v.is_pure_veg, FALSE)::BOOLEAN,
        COALESCE(v.has_offers, FALSE)::BOOLEAN,
        COALESCE(v.price_for_two, 250)::NUMERIC,
        v.status::TEXT,
        COALESCE(v.is_open, TRUE)::BOOLEAN,
        v.open_time::TEXT,
        v.close_time::TEXT,
        COALESCE(v.is_busy, FALSE)::BOOLEAN,
        v.latitude::DOUBLE PRECISION,
        v.longitude::DOUBLE PRECISION
    FROM public.vendors v
    WHERE v.is_active = TRUE 
    AND v.is_verified = TRUE
    AND (6371 * acos(
        LEAST(1.0, GREATEST(-1.0, 
            cos(radians(p_lat)) * cos(radians(COALESCE(v.latitude, p_lat))) * 
            cos(radians(COALESCE(v.longitude, p_lng)) - radians(p_lng)) + 
            sin(radians(p_lat)) * sin(radians(COALESCE(v.latitude, p_lat)))
        ))
    )) <= public.get_effective_delivery_radius(v.id) -- NOW FULLY DYNAMIC
    ORDER BY d_km ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 3. UPDATE validate_order_radius to be DYNAMIC
CREATE OR REPLACE FUNCTION validate_order_radius(v_id UUID, c_lat DOUBLE PRECISION, c_lng DOUBLE PRECISION)
RETURNS BOOLEAN AS $$
DECLARE
    v_radius NUMERIC;
    v_dist DOUBLE PRECISION;
BEGIN
    -- Get dynamic radius
    v_radius := public.get_effective_delivery_radius(v_id);

    -- Calculate distance
    SELECT (6371 * acos(
            LEAST(1.0, GREATEST(-1.0, 
                cos(radians(c_lat)) * cos(radians(COALESCE(latitude, c_lat))) * 
                cos(radians(COALESCE(longitude, c_lng)) - radians(c_lng)) + 
                sin(radians(c_lat)) * sin(radians(COALESCE(latitude, c_lat)))
            ))
        ))
    INTO v_dist
    FROM public.vendors WHERE id = v_id;

    RETURN COALESCE(v_dist, 0) <= v_radius;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 4. UPDATE ORDER TRIGGER (Final Defense)
CREATE OR REPLACE FUNCTION public.enforce_order_delivery_radius()
RETURNS TRIGGER AS $$
DECLARE
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_radius NUMERIC;
    v_distance DOUBLE PRECISION;
BEGIN
    -- Get vendor coordinates
    SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng
    FROM public.vendors
    WHERE id = NEW.vendor_id;
    
    -- Get dynamic radius
    v_radius := public.get_effective_delivery_radius(NEW.vendor_id);

    IF v_vendor_lat IS NULL OR v_vendor_lng IS NULL THEN
        RETURN NEW;
    END IF;

    -- Calculate distance accurately
    v_distance := (6371 * acos(
            LEAST(1.0, GREATEST(-1.0, 
                cos(radians(COALESCE(NEW.delivery_lat, NEW.customer_lat))) * cos(radians(v_vendor_lat)) * 
                cos(radians(v_vendor_lng) - radians(COALESCE(NEW.delivery_lng, NEW.customer_lng))) + 
                sin(radians(COALESCE(NEW.delivery_lat, NEW.customer_lat))) * sin(radians(v_vendor_lat))
            ))
        ));

    -- STRICT ENFORCEMENT
    IF v_distance > v_radius THEN
        RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Your location is %km away. Maximum delivery radius is %km.', 
            ROUND(v_distance::numeric, 2), v_radius;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Atomic Cleanup: Ensure the trigger is active
DROP TRIGGER IF EXISTS tr_enforce_order_radius ON public.orders;
CREATE TRIGGER tr_enforce_order_radius
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE PROCEDURE public.enforce_order_delivery_radius();

-- 6. Optional: Sync the legacy 'delivery_radius_limit' to match the new 'system_config'
-- This ensures older scripts that look for the legacy key also see the 5km limit.
UPDATE public.app_settings 
SET value = '5.0'::jsonb 
WHERE key = 'delivery_radius_limit';

COMMIT;

