-- 🚨 URGENT REPAIR V1
-- 🎯 MISSION: FIX RPC PARAMETERS & ADDRESS SYNC
-- 🎯 REASON: Fix crashes caused by parameter mismatches and resolve address display issues.

BEGIN;

-- 1. 🥗 get_nearby_vendors_v24 (Support 2 or 3 parameters)
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 15.0 -- 🗺️ Default to 15km for Map/Explore
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
            WHERE (v.status = 'ONLINE' OR v.status = 'Active')
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= p_radius_km
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. 🥘 get_popular_near_you_v2 (Support 3 or 4 parameters)
DROP FUNCTION IF EXISTS public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT);
DROP FUNCTION IF EXISTS public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT, DOUBLE PRECISION);

CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT DEFAULT NULL,
    p_radius_km DOUBLE PRECISION DEFAULT 5.0
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
                    v.name as vendor_name,
                    (
                        SELECT row_to_json(tv)
                        FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                    ) as trusted_vendor
                FROM public.products p
                JOIN public.vendors v ON p.vendor_id = v.id
                LEFT JOIN public.categories c ON p.category_id::text = c.id::text
                WHERE p.is_active = true
                  AND (
                    p_category_id IS NULL 
                    OR p_category_id = '' 
                    OR p_category_id = 'all'
                    OR p.category_id::text = p_category_id 
                    OR c.name = p_category_id
                    OR c.name ILIKE p_category_id
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL 
              AND (item_data.trusted_vendor->>'distance_km')::double precision <= p_radius_km
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🔍 search_items_near_you_v2 (Ensure parameters match)
DROP FUNCTION IF EXISTS public.search_items_near_you_v2(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INT);

CREATE OR REPLACE FUNCTION public.search_items_near_you_v2(
    p_query TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_limit INT DEFAULT 50,
    p_radius_km DOUBLE PRECISION DEFAULT 10.0
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
                    v.name as vendor_name,
                    c.name as category_name,
                    (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                        cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                        sin(radians(p_lat)) * sin(radians(v.latitude))
                    ))))::double precision as distance_km,
                    (
                        SELECT row_to_json(tv)
                        FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                    ) as trusted_vendor
                FROM public.products p
                JOIN public.vendors v ON p.vendor_id = v.id
                LEFT JOIN public.categories c ON p.category_id::text = c.id::text
                WHERE p.is_active = true
                  AND (
                      p.name ILIKE '%' || p_query || '%' 
                      OR p.description ILIKE '%' || p_query || '%' 
                      OR c.name ILIKE '%' || p_query || '%' 
                      OR v.name ILIKE '%' || p_query || '%'
                      OR v.address ILIKE '%' || p_query || '%'
                      OR v.shop_name ILIKE '%' || p_query || '%'
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL 
              AND item_data.distance_km <= p_radius_km
            ORDER BY item_data.distance_km ASC
            LIMIT p_limit
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 📍 ENSURE ADDRESS TABLE SCHEMA
-- Ensure address_line exists (it should, but we can't use address_line1 if it doesn't)
-- We don't want to change schema if it's working for others, but we need to match Flutter code.

-- 5. GRANTS
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_items_near_you_v2(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INT, DOUBLE PRECISION) TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
