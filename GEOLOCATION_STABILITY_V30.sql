-- 🚀 GEOLOCATION STABILITY FIX (V30.0)
-- 🎯 MISSION: STRICT 15KM RADIUS. ORDER BY DISTANCE. LOCATION-AWARE SEARCH.

BEGIN;

-- 1. 🥘 ENHANCED TRUSTED VENDOR LOGIC (Distance Limit 15km)
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
    is_trusted BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH potential_vendors AS (
        SELECT 
            v.id::text as v_id,
            v.name as v_name,
            p.price as v_price,
            (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as dist,
            COALESCE(v.rating, 5.0)::double precision as v_rating,
            p.image_url as v_image
        FROM public.products p
        JOIN public.vendors v ON p.vendor_id::text = v.id::text
        WHERE p.id::text = p_product_id
          AND v.status = 'ONLINE'
          AND p.is_active = true
          AND p.is_available = true
          -- 🌍 STRICT 15KM RADIUS FOR DELIVERY
          AND (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) <= 15.0
    )
    SELECT 
        v_id,
        v_name,
        v_price,
        dist,
        v_rating,
        (20 + (dist * 5))::int as v_eta,
        v_image,
        TRUE as v_is_trusted
    FROM potential_vendors
    ORDER BY dist ASC, v_rating DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- 2. 🌟 LOCATION-AWARE HOME FEED (Ordered by Proximity)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(item_data)
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
              AND (p_category_id IS NULL OR p.category_id::text = p_category_id OR c.name ILIKE p_category_id)
        ) item_data
        WHERE item_data.trusted_vendor IS NOT NULL
        -- 🌍 ORDER BY DISTANCE (Proximity first)
        ORDER BY 
            (item_data.trusted_vendor->>'distance_km')::double precision ASC,
            (CASE WHEN item_data.is_popular = true THEN 0 ELSE 1 END) ASC
        LIMIT 100
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🔍 LOCATION-AWARE SEARCH (Crucial for user request)
CREATE OR REPLACE FUNCTION public.search_items_near_you_v2(
    p_query TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_limit INT DEFAULT 50
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(item_data)
        FROM (
            SELECT 
                p.*,
                v.name as vendor_name,
                c.name as category_name,
                (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance_km,
                (
                    SELECT row_to_json(tv)
                    FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                ) as trusted_vendor
            FROM public.products p
            JOIN public.vendors v ON p.vendor_id = v.id
            LEFT JOIN public.categories c ON p.category_id::text = c.id::text
            WHERE p.is_active = true
              AND (p.name ILIKE '%' || p_query || '%' OR p.description ILIKE '%' || p_query || '%' OR c.name ILIKE '%' || p_query || '%' OR v.name ILIKE '%' || p_query || '%')
        ) item_data
        WHERE item_data.trusted_vendor IS NOT NULL -- This automatically enforces 15km via get_trusted_vendor_for_item_v2
        ORDER BY item_data.distance_km ASC
        LIMIT p_limit
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Permissions
GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_items_near_you_v2 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
