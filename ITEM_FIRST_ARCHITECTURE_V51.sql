-- 🏗️ ITEM-FIRST ARCHITECTURE & TRUSTED VENDOR SYSTEM (V51.0)
-- 🎯 MISSION: Transition UnivFoods to an Item-First platform where vendors are pooled.

BEGIN;

-- 1. 🥘 FOODS TABLE ENHANCEMENT
ALTER TABLE public.foods ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT false;
ALTER TABLE public.foods ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- 2. 🏪 VENDORS TABLE ENHANCEMENT
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT true;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS delivery_radius_km DOUBLE PRECISION DEFAULT 10.0;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS prep_time_avg_mins INT DEFAULT 20;

-- 3. 🔗 VENDOR-FOOD MAPPING (The heart of the Item-First system)
-- This table allows multiple vendors to sell the same food item with different prices.
CREATE TABLE IF NOT EXISTS public.vendor_foods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id UUID NOT IF EXISTS REFERENCES public.vendors(id) ON DELETE CASCADE,
    food_id UUID NOT IF EXISTS REFERENCES public.foods(id) ON DELETE CASCADE,
    price DOUBLE PRECISION NOT NULL,
    image TEXT, -- Vendor-specific image (optional)
    stock_status TEXT DEFAULT 'AVAILABLE', -- AVAILABLE, OUT_OF_STOCK
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(vendor_id, food_id)
);

-- 4. 🛒 CART ENHANCEMENT
ALTER TABLE public.cart ADD COLUMN IF NOT EXISTS locked_vendor_id UUID; -- For non-popular items

-- 5. 📦 ORDER SPLITTING SUPPORT
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS master_order_id UUID;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS vendor_id UUID; -- Redundant but good for backward compat

-- 6. 🚀 TRUSTED VENDOR DISCOVERY RPC
-- This function finds the best vendor for a popular item relative to the user.
CREATE OR REPLACE FUNCTION public.get_trusted_vendor_for_item(
    p_food_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS TABLE (
    vendor_id UUID,
    vendor_name TEXT,
    price DOUBLE PRECISION,
    distance DOUBLE PRECISION,
    rating DOUBLE PRECISION,
    prep_time INT,
    image TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.id,
        v.name,
        vf.price,
        -- Haversine formula for distance
        (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance,
        v.rating,
        v.prep_time_avg_mins,
        COALESCE(vf.image, f.image) as image
    FROM public.vendor_foods vf
    JOIN public.vendors v ON vf.vendor_id = v.id
    JOIN public.foods f ON vf.food_id = f.id
    WHERE vf.food_id = p_food_id
      AND v.is_active = true
      AND v.is_open = true
      AND vf.is_available = true
    ORDER BY distance ASC, v.rating DESC, v.prep_time_avg_mins ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- 7. 🚀 POPULAR ITEMS HOME FEED RPC
-- Fetches items and their "Trusted Vendor" data in one go.
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
                f.*,
                c.name as category_name,
                (
                    SELECT row_to_json(tv)
                    FROM public.get_trusted_vendor_for_item(f.id, p_lat, p_lng) tv
                ) as trusted_vendor
            FROM public.foods f
            JOIN public.categories c ON f.category_id = c.id
            WHERE f.is_popular = true 
              AND f.is_active = true
              AND (p_category_id IS NULL OR f.category_id = p_category_id)
        ) item_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 9. 🚀 MASTER ORDER PLACEMENT (MULTI-VENDOR SPLITTING)
-- This function takes a grouped cart and creates multiple orders linked by a master_order_id.
CREATE OR REPLACE FUNCTION public.place_order_v4(
    p_customer_id TEXT,
    p_vendor_items JSONB, -- Format: [{"vendor_id": UUID, "items": [...], "total": double}, ...]
    p_address TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '',
    p_payment_status TEXT DEFAULT 'PENDING'
)
RETURNS UUID AS $$
DECLARE
    v_master_id UUID;
    v_sub_order JSONB;
BEGIN
    v_master_id := gen_random_uuid();

    -- Loop through each vendor's grouped items and create a sub-order
    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        INSERT INTO public.orders (
            id, master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, payment_method, payment_status,
            cooking_instructions
        ) VALUES (
            gen_random_uuid(),
            v_master_id,
            p_customer_id,
            (v_sub_order->>'vendor_id')::uuid,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.place_order_v4 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
