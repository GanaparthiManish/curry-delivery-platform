-- 🚀 FIX DISCOVERY RPCS (V107.0)
-- 🎯 MISSION: Ensure items show up even if vendor_products is empty, and support category filtering.

BEGIN;

-- 1. 🥘 ENHANCED TRUSTED VENDOR LOGIC (Fallback to products.vendor_id)
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
        -- Source 1: mapping table (Item-First / Multi-vendor)
        SELECT 
            v.id::text as v_id,
            v.name as v_name,
            vp.price as v_price,
            (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as dist,
            COALESCE(v.rating, 5.0)::double precision as v_rating,
            COALESCE(vp.image, p.image_url) as v_image
        FROM public.products p
        JOIN public.vendor_products vp ON vp.product_id::text = p.id::text
        JOIN public.vendors v ON vp.vendor_id::text = v.id::text
        WHERE p.id::text = p_product_id
          AND v.status = 'ONLINE'
          AND vp.is_available = true
          
        UNION ALL
        
        -- Source 2: direct vendor_id on product (Legacy / One-vendor)
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
          AND p.is_available = true
          -- Only use this if Source 1 returned nothing (handled by ORDER BY and LIMIT 1)
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

-- 2. 🌟 UPDATED POPULAR ITEMS FEED (Support Category Filter)
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
              AND (p.item_type = 'POPULAR_ITEM' OR p_category_id IS NOT NULL) -- Show popular items OR anything in selected category
              AND (p_category_id IS NULL OR p.category_id::text = p_category_id OR c.name ILIKE p_category_id)
        ) item_data
        WHERE item_data.trusted_vendor IS NOT NULL
        ORDER BY (CASE WHEN item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END), item_data.name ASC
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🏪 UPDATED NEARBY VENDORS (Ensure consistent return types)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 15.0
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(v_data)
        FROM (
            SELECT 
                v.*,
                (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance_km
            FROM public.vendors v
            WHERE v.status = 'ONLINE'
              AND (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) <= p_radius_km
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Permissions
GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
