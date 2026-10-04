-- 🧩 UNIVERSAL COMPATIBILITY OVERHAUL (V49.0)
-- 🎯 MISSION: FIX OLD APKs + RESTORE ALL MISSING RPC OVERLOADS
-- 🎯 REASON: Old APKs pass 'p_radius' which was causing 404 errors.

BEGIN;

-- 1. 🥘 get_trusted_vendor_for_item_v2 (Foundation)
-- This is used by all feed functions.
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
            p.price::double precision as v_price,
            (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v.latitude))
            ))))::double precision as dist,
            COALESCE(v.rating, 5.0)::double precision as v_rating,
            p.image_url as v_image
        FROM public.products p
        JOIN public.vendors v ON p.vendor_id::text = v.id::text
        WHERE p.id::text = p_product_id
          AND v.status = 'ONLINE' -- 🟢 ONLY SHOW ONLINE SHOPS
          AND p.is_active = true
          AND p.is_available = true
          -- 🌍 STRICT 5KM RADIUS
          AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v.latitude))
          )))) <= 5.0
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

-- 2. 🥘 get_popular_near_you_v2 (New Version: 3 params with TEXT)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT
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
                  AND (p_category_id IS NULL OR p_category_id = '' OR p.category_id::text = p_category_id OR c.name ILIKE p_category_id)
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🥘 get_popular_near_you_v2 (Compatibility: 2 params)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_popular_near_you_v2(p_lat, p_lng, NULL::TEXT);
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 🥘 get_popular_near_you_v2 (Compatibility: 3 params with DOUBLE)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    -- We ignore p_radius and use our strict 5km logic for stability
    RETURN public.get_popular_near_you_v2(p_lat, p_lng, NULL::TEXT);
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. 🥘 get_nearby_vendors_v24 (Compatibility: Multiple overloads)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(v_data)
        FROM (
            SELECT v.*, 
                (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
                ))))::double precision as distance_km
            FROM public.vendors v
            WHERE v.status = 'ONLINE'
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= 5.0
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

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

-- 6. 🥘 get_nearby_vendors_v23 (Legacy Compatibility)
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

-- 7. 🥘 get_popular_items_feed (Legacy Compatibility)
CREATE OR REPLACE FUNCTION public.get_popular_items_feed(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_popular_near_you_v2(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;

-- 8. 🥘 get_popular_near_you (Legacy Compatibility)
CREATE OR REPLACE FUNCTION public.get_popular_near_you(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_popular_near_you_v2(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;

-- Permissions for all overloads
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_items_feed(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
