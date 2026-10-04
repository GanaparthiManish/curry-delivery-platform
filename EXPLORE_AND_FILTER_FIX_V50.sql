-- 🗺️ EXPLORE & FILTER REPAIR (V50.0)
-- 🎯 MISSION: FIX CATEGORY FILTERING + RESTORE MAP VISIBILITY
-- 🎯 REASON: Ensure 'Biryani' only shows Biryani, and Map shows all vendors.

BEGIN;

-- 🧹 CLEANUP OLD VERSIONS (Fixes 42P13 error)
DROP FUNCTION IF EXISTS public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT);
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

-- 1. 🥘 get_popular_near_you_v2 (STRICT FILTERING)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(final_data)
        FROM (
            SELECT *
            FROM (
                SELECT 
                    p.*,
                    c.name as category_name,
                    (
                        SELECT row_to_json(tv)
                        FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                    ) as trusted_vendor
                FROM public.products p
                LEFT JOIN public.categories c ON p.category_id::text = c.id::text
                WHERE p.is_active = true
                  AND (
                    p_category_id IS NULL 
                    OR p_category_id = '' 
                    OR p_category_id = 'all'
                    OR p.category_id::text = p_category_id 
                    OR c.name ILIKE p_category_id
                    OR p.item_type ILIKE p_category_id
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL -- This enforces 5km & ONLINE status for ordering
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. 🗺️ get_nearby_vendors_v24 (RESTORE MAP VISIBILITY)
-- We remove the status = 'ONLINE' filter for the map so the user can see all shops.
-- But we still calculate the distance.
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
            WHERE (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= 50.0 -- 🌍 Increased to 50km for Map visibility, but app will still show distance
            ORDER BY (v.status = 'ONLINE') DESC, distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🥘 Overloads for Compatibility
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_nearby_vendors_v24(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;

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
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
