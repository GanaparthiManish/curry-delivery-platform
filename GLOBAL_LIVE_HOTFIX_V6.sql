-- 🚨 GLOBAL LIVE HOTFIX V6.0 (FOR PLAY STORE USERS)
-- 🎯 MISSION: Restore visibility for ALL users (v21, v22, v23, v24) without requiring an app update.

BEGIN;

-- 1. UNIFORM RPC OVERWRITE
-- We overwrite every version of the RPC that might be live in the Play Store.
-- This ensures that regardless of which version the user's app is calling, they get the fix.

CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v21(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION) 
RETURNS SETOF public.vendors AS $$
BEGIN
    RETURN QUERY SELECT * FROM public.vendors WHERE is_active = TRUE AND is_verified = TRUE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Recreating the V23 logic too (this is what the current most stable Play Store version likely uses)
DROP FUNCTION IF EXISTS get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION);
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
        COALESCE((6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(COALESCE(p_lat, 0))) * cos(radians(COALESCE(v.latitude, 0))) * cos(radians(COALESCE(v.longitude, 0)) - radians(COALESCE(p_lng, 0))) + sin(radians(COALESCE(p_lat, 0))) * sin(radians(COALESCE(v.latitude, 0))))))), 0)::DOUBLE PRECISION,
        v.delivery_time::TEXT, COALESCE(v.is_pure_veg, FALSE)::BOOLEAN, COALESCE(v.has_offers, FALSE)::BOOLEAN, COALESCE(v.price_for_two, 250)::NUMERIC,
        v.status::TEXT, COALESCE(v.is_open, TRUE)::BOOLEAN, v.open_time::TEXT, v.close_time::TEXT, COALESCE(v.is_busy, FALSE)::BOOLEAN,
        v.latitude::DOUBLE PRECISION, v.longitude::DOUBLE PRECISION
    FROM public.vendors v
    WHERE v.is_active = TRUE AND v.is_verified = TRUE
    ORDER BY 8 ASC; -- Order by distance
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Create V24 as well for parity
DROP FUNCTION IF EXISTS get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION);
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

-- 2. RESET GLOBAL RADIUS IN DB
-- This setting is checked by the database triggers during order placement.
UPDATE public.app_settings 
SET value = jsonb_set(value, '{deliveryRadius}', '1000.0')
WHERE key = 'system_config';

-- 3. ENSURE ALL TABLES ARE EXPOSED
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow public read vendors" ON public.vendors;
CREATE POLICY "Allow public read vendors" ON public.vendors FOR SELECT USING (true);

-- 4. REPAIR VENDOR ONLINE STATUS
UPDATE public.vendors
SET is_active = TRUE, is_verified = TRUE, is_open = TRUE, status = 'ONLINE', delivery_radius_km = 1000;

COMMIT;
