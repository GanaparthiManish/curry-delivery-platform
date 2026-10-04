-- 🏆 UNIVFOODS FINAL LOGIC UPGRADE (V55.0)
-- 🎯 MISSION: Implement exact requirements for Item Type, Trusted Vendor, and Order Splitting.

BEGIN;

-- ==========================================
-- 1. 🏗️ PRODUCT ENHANCEMENTS
-- ==========================================

-- Add item_type column
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'products' AND column_name = 'item_type') THEN
        ALTER TABLE public.products ADD COLUMN item_type TEXT DEFAULT 'NORMAL_VENDOR_ITEM';
    END IF;
END $$;

-- Migrate existing is_popular data
UPDATE public.products SET item_type = 'POPULAR_ITEM' WHERE is_popular = true;
UPDATE public.products SET item_type = 'NORMAL_VENDOR_ITEM' WHERE is_popular = false OR is_popular IS NULL;

-- ==========================================
-- 2. 🥘 ENHANCED DISCOVERY RPCS
-- ==========================================

-- Updated Trusted Vendor Logic (Includes green tick indicator)
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
    SELECT 
        v.id::text,
        v.name,
        vp.price,
        (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance_km,
        COALESCE(v.rating, 5.0)::double precision as rating,
        (20 + ( (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) * 5 ))::int as eta_mins,
        COALESCE(vp.image, p.image_url) as image,
        TRUE as is_trusted
    FROM public.vendor_products vp
    JOIN public.vendors v ON vp.vendor_id::text = v.id::text
    JOIN public.products p ON vp.product_id::text = p.id::text
    WHERE vp.product_id::text = p_product_id
      AND v.status = 'ONLINE'
      AND v.is_approved = true
      AND vp.is_available = true
    ORDER BY distance_km ASC, rating DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get ALL vendors selling a Normal Item
CREATE OR REPLACE FUNCTION public.get_all_vendors_for_item(
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
    image TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id::text,
        v.name,
        vp.price,
        (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance_km,
        COALESCE(v.rating, 5.0)::double precision as rating,
        (20 + ( (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) * 5 ))::int as eta_mins,
        COALESCE(vp.image, p.image_url) as image
    FROM public.vendor_products vp
    JOIN public.vendors v ON vp.vendor_id::text = v.id::text
    JOIN public.products p ON vp.product_id::text = p.id::text
    WHERE vp.product_id::text = p_product_id
      AND v.status = 'ONLINE'
      AND v.is_approved = true
      AND vp.is_available = true
    ORDER BY distance_km ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Updated Popular Items Feed
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(item_data)
        FROM (
            SELECT 
                p.*,
                (
                    SELECT row_to_json(tv)
                    FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                ) as trusted_vendor
            FROM public.products p
            WHERE p.item_type = 'POPULAR_ITEM'
              AND p.is_active = true
        ) item_data
        WHERE item_data.trusted_vendor IS NOT NULL
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- 3. 🛡️ PERMISSIONS
-- ==========================================

GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_all_vendors_for_item TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2 TO anon, authenticated, service_role;

COMMIT;
