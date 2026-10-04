-- 📍 SMART LOGISTICS REPAIR V8.0
-- 🎯 MISSION: Enforce 5km limit for live users, but ALLOW special visibility for test vendors.

BEGIN;

-- 1. IDENTIFY YOUR TEST VENDOR (Royal Curry)
-- Setting its radius to 1000km so it's always visible for your testing.
UPDATE public.vendors
SET delivery_radius_km = 1000.0, radius_km = 1000.0
WHERE name ILIKE '%Royal%';

-- 2. ENSURE ALL OTHER VENDORS ARE AT 5KM
UPDATE public.vendors
SET delivery_radius_km = 5.0, radius_km = 5.0
WHERE name NOT ILIKE '%Royal%';

-- 3. FIX THE RPC TO HANDLE PRECISION ERRORS
-- Adding a slight buffer (0.1km) and ensuring distance calculations are robust.
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
    -- ENFORCING RADIUS: Checks vendor-specific radius first (Royal is 1000km, rest are 5km)
    AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(COALESCE(p_lat, 0))) * cos(radians(COALESCE(v.latitude, 0))) * cos(radians(COALESCE(v.longitude, 0)) - radians(COALESCE(p_lng, 0))) + sin(radians(COALESCE(p_lat, 0))) * sin(radians(COALESCE(v.latitude, 0))))))) <= (public.get_effective_delivery_radius(v.id) + 0.1)
    ORDER BY d_km ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Snc V24
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

COMMIT;
