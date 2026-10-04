-- 🚀 ULTIMATE STABILITY HOTFIX (V46.0)
-- 🎯 MISSION: FIX HOME FEED (Popular/Normal Items) + REAL-TIME TRACKING
-- 🎯 FIXING SQL Error: "column must appear in the GROUP BY clause"

BEGIN;

-- 1. 🥘 REPAIR TRUSTED VENDOR LOGIC (STRICT 5KM RADIUS)
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
            (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v.latitude))
            )))) as dist,
            COALESCE(v.rating, 5.0)::double precision as v_rating,
            p.image_url as v_image
        FROM public.products p
        JOIN public.vendors v ON p.vendor_id::text = v.id::text
        WHERE p.id::text = p_product_id
          AND v.status = 'ONLINE'
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

-- 2. 🌟 REPAIR HOME FEED (Fixing the GROUP BY error)
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
                  AND (p_category_id IS NULL OR p.category_id::text = p_category_id OR c.name ILIKE p_category_id)
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL -- This enforces 5km
            ORDER BY 
                (item_data.trusted_vendor->>'distance_km')::double precision ASC,
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🔍 REPAIR SEARCH (Fixing the GROUP BY error)
CREATE OR REPLACE FUNCTION public.search_items_near_you_v2(
    p_query TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_limit INT DEFAULT 50
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
                    )))) as distance_km,
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
            WHERE item_data.trusted_vendor IS NOT NULL -- This enforces 5km
            ORDER BY item_data.distance_km ASC
            LIMIT p_limit
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 🏪 REPAIR NEARBY VENDORS (STRICT 5KM)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 5.0
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
                )))) as distance_km
            FROM public.vendors v
            WHERE v.status = 'ONLINE'
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= p_radius_km
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. 🛰️ REPAIR REAL-TIME TRACKING PERMISSIONS & PUBLICATION
-- Ensure tables are in the publication
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_riders; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.orders; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.order_live_tracking; EXCEPTION WHEN others THEN NULL; END $$;

-- Ensure RLS allows public viewing of tracking (essential for customer app)
ALTER TABLE public.delivery_riders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view rider locations for tracking" ON public.delivery_riders;
CREATE POLICY "Public can view rider locations for tracking" ON public.delivery_riders FOR SELECT USING (true);

ALTER TABLE public.order_live_tracking ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view order tracking history" ON public.order_live_tracking;
CREATE POLICY "Public can view order tracking history" ON public.order_live_tracking FOR SELECT USING (true);

-- 6. 🕒 ENSURE TRACKING COLUMNS EXIST
ALTER TABLE public.order_live_tracking ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.order_live_tracking ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

-- 7. 🚀 REPAIR RIDER LOCATION UPDATE (v43)
-- Ensure it updates the rider table correctly for realtime
CREATE OR REPLACE FUNCTION public.update_rider_location_v43(
    p_rider_id TEXT,
    p_order_id UUID DEFAULT NULL,
    p_lat DOUBLE PRECISION DEFAULT 0,
    p_lng DOUBLE PRECISION DEFAULT 0,
    p_heading DOUBLE PRECISION DEFAULT 0,
    p_speed DOUBLE PRECISION DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
    -- Update Rider table (The source of truth for the Map)
    UPDATE public.delivery_riders SET
        current_lat = p_lat,
        current_lng = p_lng,
        last_lat = p_lat,
        last_lng = p_lng,
        bearing = p_heading,
        speed = p_speed,
        last_gps_update = now(),
        updated_at = now()
    WHERE id::text = p_rider_id;

    -- Update Active Order snapshot
    IF p_order_id IS NOT NULL THEN
        UPDATE public.orders SET
            rider_lat = p_lat,
            rider_lng = p_lng,
            updated_at = now()
        WHERE id = p_order_id;
        
        -- History entry
        INSERT INTO public.order_live_tracking (order_id, rider_id, rider_lat, rider_lng, speed, heading)
        VALUES (p_order_id, p_rider_id::uuid, p_lat, p_lng, p_speed, p_heading);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Permissions
GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_items_near_you_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_rider_location_v43 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
