-- 🛡️ ULTIMATE SCHEMA CONSOLIDATION & REPAIR (V54.1)
-- 🎯 MISSION: Fix "master_order_id" missing and correct "NOT IF EXISTS" syntax errors.
-- 🎯 MISSION: Ensure Item-First architecture and Stability fixes are applied without errors.

BEGIN;

-- ==========================================
-- 1. 🏗️ SCHEMA REPAIR (ENSURE COLUMNS EXIST)
-- ==========================================

-- Orders Table
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS master_order_id TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS total_amount DOUBLE PRECISION;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS status TEXT;

-- Products Table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT false;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
-- ENSURE PRIMARY KEY EXISTS (Fixes 42830)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_name = 'products' AND constraint_type = 'PRIMARY KEY') THEN
        ALTER TABLE public.products ADD PRIMARY KEY (id);
    END IF;
END $$;

-- Vendors Table
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT true;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS delivery_radius_km DOUBLE PRECISION DEFAULT 10.0;
ALTER TABLE public.vendors ADD COLUMN IF NOT EXISTS prep_time_avg_mins INT DEFAULT 20;

-- ==========================================
-- 2. 🥘 VENDOR-PRODUCT MAPPING (TEXT IDs for Compatibility)
-- ==========================================

CREATE TABLE IF NOT EXISTS public.vendor_products (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
    vendor_id TEXT NOT NULL REFERENCES public.vendors(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    price DOUBLE PRECISION NOT NULL,
    image TEXT, 
    stock_status TEXT DEFAULT 'AVAILABLE', 
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(vendor_id, product_id)
);

-- ==========================================
-- 3. 🛡️ STABILIZED VIEW (With Safe Column Access)
-- ==========================================

DROP VIEW IF EXISTS public.order_tracking_stabilized_v1;
CREATE OR REPLACE VIEW public.order_tracking_stabilized_v1 AS
SELECT 
    o.id as order_id,
    o.id as id,
    o.master_order_id,
    o.customer_id::text as customer_id,
    o.vendor_id,
    COALESCE(v.name, 'Shop') as vendor_name,
    COALESCE(v.logo_url, v.image_url) as vendor_logo,
    o.items,
    COALESCE(o.total_amount, 0) as total,
    o.total_amount,
    COALESCE(o.order_status, o.status, 'PLACED') as status,
    o.order_status,
    o.payment_method,
    o.payment_status,
    o.delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.created_at,
    o.updated_at,
    -- Rider Info
    o.rider_id,
    dr.name as rider_name,
    dr.phone as rider_phone,
    dr.current_lat as rider_lat,
    dr.current_lng as rider_lng,
    dr.bearing as rider_bearing,
    dr.speed as rider_speed,
    -- Status Display
    CASE 
        WHEN COALESCE(o.order_status, o.status) = 'PLACED' THEN 'Order Placed'
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED' THEN 'Preparing'
        WHEN COALESCE(o.order_status, o.status) = 'COOKING' THEN 'Cooking'
        WHEN COALESCE(o.order_status, o.status) = 'READY' THEN 'Food is Ready'
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP' THEN 'On the Way'
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED' THEN 'Delivered'
        WHEN COALESCE(o.order_status, o.status) = 'CANCELLED' THEN 'Cancelled'
        ELSE COALESCE(o.order_status, o.status)
    END as status_display,
    -- Progress Step (1-5)
    CASE 
        WHEN COALESCE(o.order_status, o.status) = 'PLACED' THEN 1
        WHEN COALESCE(o.order_status, o.status) IN ('ACCEPTED', 'COOKING') THEN 2
        WHEN COALESCE(o.order_status, o.status) = 'READY' THEN 3
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP' THEN 4
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED' THEN 5
        ELSE 1
    END as current_step
FROM public.orders o
LEFT JOIN public.vendors v ON o.vendor_id::text = v.id::text
LEFT JOIN public.delivery_riders dr ON o.rider_id::text = dr.id::text;

GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

-- ==========================================
-- 4. 🚀 PLACE ORDER V4 (Multi-Vendor Splitting)
-- ==========================================

CREATE OR REPLACE FUNCTION public.place_order_v4(
    p_customer_id TEXT,
    p_vendor_items JSONB, 
    p_address TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '',
    p_payment_status TEXT DEFAULT 'PENDING'
)
RETURNS TEXT AS $$
DECLARE
    v_master_id TEXT;
    v_sub_order JSONB;
BEGIN
    v_master_id := gen_random_uuid()::TEXT;

    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        INSERT INTO public.orders (
            id, master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions
        ) VALUES (
            gen_random_uuid()::TEXT,
            v_master_id,
            p_customer_id,
            (v_sub_order->>'vendor_id')::TEXT,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            'PLACED',
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 4.5 🚀 ITEM-FIRST DISCOVERY (TRUSTED VENDOR)
-- ==========================================

CREATE OR REPLACE FUNCTION public.get_trusted_vendor_for_item(
    p_product_id TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS TABLE (
    vendor_id TEXT,
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
        vp.price,
        (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) as distance,
        v.rating,
        v.prep_time_avg_mins,
        COALESCE(vp.image, p.image_url) as image
    FROM public.vendor_products vp
    JOIN public.vendors v ON vp.vendor_id = v.id
    JOIN public.products p ON vp.product_id = p.id
    WHERE vp.product_id = p_product_id
      AND v.is_active = true
      AND v.is_open = true
      AND vp.is_available = true
    ORDER BY distance ASC, v.rating DESC, v.prep_time_avg_mins ASC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.get_popular_items_feed(
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
                    FROM public.get_trusted_vendor_for_item(p.id, p_lat, p_lng) tv
                ) as trusted_vendor
            FROM public.products p
            JOIN public.categories c ON p.category_id = c.id
            WHERE p.is_popular = true 
              AND p.is_active = true
              AND (p_category_id IS NULL OR p.category_id = p_category_id)
        ) item_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_items_feed TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cancel_order_stabilized_v2(
    p_order_id TEXT,
    p_customer_id TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_order RECORD;
BEGIN
    SELECT * INTO v_order 
    FROM public.orders 
    WHERE id::text = p_order_id::text 
      AND customer_id::text = p_customer_id::text
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order not found or unauthorized');
    END IF;

    IF v_order.order_status NOT IN ('PLACED', 'PAYMENT_PENDING') AND v_order.status NOT IN ('PLACED', 'PAYMENT_PENDING') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot cancel order in this state');
    END IF;

    UPDATE public.orders 
    SET order_status = 'CANCELLED',
        status = 'CANCELLED',
        updated_at = now()
    WHERE id::text = p_order_id::text;

    RETURN jsonb_build_object('success', true, 'message', 'Order cancelled successfully');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.rider_deliver_order_v3(
    p_order_id TEXT
)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.orders 
    SET order_status = 'DELIVERED',
        status = 'DELIVERED',
        payment_status = 'SUCCESS',
        updated_at = now()
    WHERE id::text = p_order_id::text;

    UPDATE public.delivery_riders 
    SET wallet_balance = wallet_balance + (SELECT COALESCE(total_amount, 0) * 0.1 FROM public.orders WHERE id::text = p_order_id::text)
    WHERE id::text = (SELECT rider_id::text FROM public.orders WHERE id::text = p_order_id::text);

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==========================================
-- 6. 🛡️ PERMISSIONS & RLS
-- ==========================================

GRANT EXECUTE ON FUNCTION public.place_order_v4 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_order_stabilized_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rider_deliver_order_v3 TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "Customers can view own orders" ON public.orders;
CREATE POLICY "Customers can view own orders" 
ON public.orders FOR SELECT 
USING (customer_id::text = (auth.uid())::text OR customer_id::text = 'guest_tester');

COMMIT;
NOTIFY pgrst, 'reload schema';
