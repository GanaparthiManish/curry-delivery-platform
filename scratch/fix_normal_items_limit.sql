-- 🚀 FIX NORMAL ITEMS LIMIT MIGRATION
-- 🎯 MISSION: Increase limit from 100 to 500 to prevent popular items from starving out normal items.

BEGIN;

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
                    OR c.name = p_category_id
                    OR c.name ILIKE p_category_id
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL 
              AND (item_data.trusted_vendor->>'distance_km')::double precision <= p_radius_km
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 500
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
