-- 🛒 RESTORE ITEMS & ITEM-FIRST SYNC (V106.0)
-- 🎯 MISSION: Populate vendor_foods and stabilize home feed discovery.

BEGIN;

-- 1. 📂 POPULATE VENDOR_FOODS FROM PRODUCTS
-- This bridges the gap between old Product-centric and new Item-centric architecture.
INSERT INTO public.vendor_foods (vendor_id, food_id, price, is_available)
SELECT 
    vendor_id::uuid, 
    id, 
    price, 
    is_available
FROM public.products
ON CONFLICT (vendor_id, food_id) DO UPDATE 
SET price = EXCLUDED.price, 
    is_available = EXCLUDED.is_available;

-- 2. 🌟 ENSURE POPULARITY
-- Mark items as popular so they appear in the new home feed.
UPDATE public.products SET is_popular = true WHERE is_active = true;

-- 3. 🚀 RELAX FEED RPC
-- The previous version was too strict on vendor status and distance.
CREATE OR REPLACE FUNCTION public.get_popular_items_feed(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id UUID DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(item_data)
        FROM (
            SELECT 
                p.id,
                p.name,
                p.description,
                p.image_url,
                p.price,
                p.is_veg,
                p.is_popular,
                p.category_id,
                c.name as category_name,
                (
                    SELECT jsonb_build_object(
                        'vendor_id', v.id,
                        'vendor_name', v.name,
                        'price', vf.price,
                        'rating', v.rating,
                        'distance', (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude))))
                    )
                    FROM public.vendor_foods vf
                    JOIN public.vendors v ON v.id = vf.vendor_id
                    WHERE vf.food_id = p.id 
                      AND vf.is_available = true 
                      AND v.is_active = true
                      AND v.is_open = true
                      -- Allow any status that isn't explicitly OFFLINE or BUSY if needed, 
                      -- but for now just check is_active/is_open
                    ORDER BY (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) ASC
                    LIMIT 1
                ) as trusted_vendor
            FROM public.products p
            JOIN public.categories c ON p.category_id = c.id
            WHERE p.is_active = true 
              AND p.is_popular = true
              AND (p_category_id IS NULL OR p.category_id = p_category_id)
        ) item_data
        WHERE item_data.trusted_vendor IS NOT NULL -- Only show items that have at least one nearby/active vendor
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 🚀 RELAX NEARBY VENDORS RPC
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 15.0
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    image_url TEXT,
    rating DOUBLE PRECISION,
    delivery_time TEXT,
    distance DOUBLE PRECISION,
    is_open BOOLEAN,
    cuisine_type TEXT,
    cost_for_two INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id,
        v.name,
        v.image_url,
        v.rating,
        v.delivery_time,
        (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance,
        v.is_open,
        v.cuisine_type,
        v.cost_for_two
    FROM public.vendors v
    WHERE v.is_active = true
      AND (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) <= p_radius_km
    ORDER BY distance ASC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMIT;
NOTIFY pgrst, 'reload schema';
