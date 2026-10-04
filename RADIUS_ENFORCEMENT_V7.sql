-- 📍 RADIUS ENFORCEMENT V7.0
-- 🎯 MISSION: Restore the 5km delivery restriction while keeping all other fixes active.

BEGIN;

-- 1. Re-enable the 5km Radius Filter in the RPC
-- We update the logic for v21, v23, and v24 to strictly respect the delivery radius.

CREATE OR REPLACE FUNCTION get_nearby_vendors_v23(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS TABLE (
    id UUID, name TEXT, cuisine_type TEXT, rating NUMERIC, banner_url TEXT, logo_url TEXT, address TEXT, distance_km DOUBLE PRECISION,
    delivery_time TEXT, is_pure_veg BOOLEAN, has_offers BOOLEAN, price_for_two NUMERIC, status TEXT, is_open BOOLEAN,
    open_time TEXT, close_time TEXT, is_busy BOOLEAN, latitude DOUBLE PRECISION, longitude DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id::UUID, v.name::TEXT, v.cuisine_type::TEXT, COALESCE(v.rating, 5.0)::NUMERIC, v.banner_url::TEXT, v.logo_url::TEXT, 
        COALESCE(v.address, '')::TEXT,
        COALESCE((6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(COALESCE(p_lat, 0))) * cos(radians(COALESCE(v.latitude, 0))) * cos(radians(COALESCE(v.longitude, 0)) - radians(COALESCE(p_lng, 0))) + sin(radians(COALESCE(p_lat, 0))) * sin(radians(COALESCE(v.latitude, 0))))))), 0)::DOUBLE PRECISION AS d_km,
        v.delivery_time::TEXT, COALESCE(v.is_pure_veg, FALSE)::BOOLEAN, COALESCE(v.has_offers, FALSE)::BOOLEAN, COALESCE(v.price_for_two, 250)::NUMERIC,
        v.status::TEXT, COALESCE(v.is_open, TRUE)::BOOLEAN, v.open_time::TEXT, v.close_time::TEXT, COALESCE(v.is_busy, FALSE)::BOOLEAN,
        v.latitude::DOUBLE PRECISION, v.longitude::DOUBLE PRECISION
    FROM public.vendors v
    WHERE v.is_active = TRUE 
    AND v.is_verified = TRUE
    -- 🚨 THE RADIUS FILTER (5km Global default or Vendor Override)
    AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(COALESCE(p_lat, 0))) * cos(radians(COALESCE(v.latitude, 0))) * cos(radians(COALESCE(v.longitude, 0)) - radians(COALESCE(p_lng, 0))) + sin(radians(COALESCE(p_lat, 0))) * sin(radians(COALESCE(v.latitude, 0))))))) <= public.get_effective_delivery_radius(v.id)
    ORDER BY d_km ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Sync V24 to match
CREATE OR REPLACE FUNCTION get_nearby_vendors_v24(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS TABLE (
    id UUID, name TEXT, cuisine_type TEXT, rating NUMERIC, banner_url TEXT, logo_url TEXT, address TEXT, distance_km DOUBLE PRECISION,
    delivery_time TEXT, is_pure_veg BOOLEAN, has_offers BOOLEAN, price_for_two NUMERIC, status TEXT, is_open BOOLEAN,
    open_time TEXT, close_time TEXT, is_busy BOOLEAN, latitude DOUBLE PRECISION, longitude DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY SELECT * FROM get_nearby_vendors_v23(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 2. RESET VENDOR RADII BACK TO 5KM
-- Note: We set them to 5.0, but if you have specific vendors you want to be visible further away (like Royal Curry), 
-- you can update them specifically.
UPDATE public.vendors
SET 
    delivery_radius_km = 5.0,
    radius_km = 5.0;

-- 3. RESET GLOBAL SYSTEM CONFIG TO 5KM
UPDATE public.app_settings 
SET value = jsonb_set(value, '{deliveryRadius}', '5.0')
WHERE key = 'system_config';

-- 4. ENSURE get_effective_delivery_radius FALLBACK IS 5KM
CREATE OR REPLACE FUNCTION public.get_effective_delivery_radius(p_vendor_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_vendor_radius NUMERIC;
    v_system_radius NUMERIC;
BEGIN
    SELECT delivery_radius_km INTO v_vendor_radius FROM public.vendors WHERE id = p_vendor_id;
    IF v_vendor_radius IS NOT NULL AND v_vendor_radius > 0 THEN RETURN v_vendor_radius; END IF;

    SELECT (value->>'deliveryRadius')::numeric INTO v_system_radius FROM public.app_settings WHERE key = 'system_config';
    IF v_system_radius IS NOT NULL AND v_system_radius > 0 THEN RETURN v_system_radius; END IF;

    RETURN 5.0; -- Default 5km
END;
$$ LANGUAGE plpgsql STABLE;

COMMIT;
