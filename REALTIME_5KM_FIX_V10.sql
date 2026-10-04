-- 🚀 REAL-TIME 5KM RADIUS FIX V10.0
-- 🎯 MISSION: Implement STRICT 5km radius with full REAL-TIME synchronization.

BEGIN;

-- 1. DROP FUNCTIONS FIRST TO PREVENT PARAMETER ERRORS
DROP FUNCTION IF EXISTS get_nearby_vendors_v21(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS get_nearby_vendors_v22(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS validate_order_radius(UUID, DOUBLE PRECISION, DOUBLE PRECISION);

-- 2. CREATE STRICT 5KM RPC
-- This uses exactly 5.0km as the hard limit.
CREATE OR REPLACE FUNCTION get_nearby_vendors_v24(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
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
    AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(COALESCE(p_lat, 0))) * cos(radians(COALESCE(v.latitude, 0))) * cos(radians(COALESCE(v.longitude, 0)) - radians(COALESCE(p_lng, 0))) + sin(radians(COALESCE(p_lat, 0))) * sin(radians(COALESCE(v.latitude, 0))))))) <= 5.0
    ORDER BY d_km ASC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Overwrite v23/v21 with the same strict 5km logic
CREATE OR REPLACE FUNCTION get_nearby_vendors_v23(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS TABLE (
    id UUID, name TEXT, cuisine_type TEXT, rating NUMERIC, banner_url TEXT, logo_url TEXT, address TEXT, distance_km DOUBLE PRECISION,
    delivery_time TEXT, is_pure_veg BOOLEAN, has_offers BOOLEAN, price_for_two NUMERIC, status TEXT, is_open BOOLEAN,
    open_time TEXT, close_time TEXT, is_busy BOOLEAN, latitude DOUBLE PRECISION, longitude DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY SELECT * FROM get_nearby_vendors_v24(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 3. FIX RADIUS VALIDATION FOR CHECKOUT
CREATE OR REPLACE FUNCTION public.validate_order_radius(p_vendor_id UUID, p_user_lat DOUBLE PRECISION, p_user_lng DOUBLE PRECISION)
RETURNS BOOLEAN AS $$
DECLARE
    v_dist DOUBLE PRECISION;
BEGIN
    SELECT 6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(p_user_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_user_lng)) + sin(radians(p_user_lat)) * sin(radians(v.latitude)))))
    INTO v_dist FROM public.vendors v WHERE id = p_vendor_id;
    
    RETURN COALESCE(v_dist, 0) <= 5.0;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 4. FORCE ALL TO 5KM
UPDATE public.vendors
SET delivery_radius_km = 5.0, radius_km = 5.0;

UPDATE public.app_settings 
SET value = jsonb_set(value, '{deliveryRadius}', '5.0')
WHERE key = 'system_config';

-- 5. REAL-TIME REPLICATION FOR VENDORS
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'vendors'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.vendors;
    END IF;
END $$;

COMMIT;
