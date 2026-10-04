-- 🛠️ UNIVERSAL RESTORATION SCRIPT (V107)
-- 🎯 MISSION: Fix Item Feed, Order Cancellation, and Type Mismatches
-- 🚀 ACTION: Copy and paste this into your Supabase SQL Editor

BEGIN;

-- 1. 🛡️ ENSURE TABLE STRUCTURE IS STABLE
ALTER TABLE public.products ALTER COLUMN price TYPE NUMERIC;
ALTER TABLE public.vendor_foods ALTER COLUMN price TYPE NUMERIC;

-- 2. 🛡️ FIX POPULAR ITEMS FEED (Resolved Numeric vs Double Precision error)
DROP FUNCTION IF EXISTS public.get_popular_items_feed(double precision, double precision);
DROP FUNCTION IF EXISTS public.get_popular_items_feed(double precision, double precision, uuid);

CREATE OR REPLACE FUNCTION public.get_popular_items_feed(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id UUID DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    result JSON;
BEGIN
    SELECT json_agg(item_data) INTO result FROM (
        SELECT 
            p.id,
            p.name,
            p.description,
            p.image_url,
            p.price::NUMERIC, -- Explicit cast to ensure compatibility
            p.is_veg,
            p.is_popular,
            p.category_id,
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
                ORDER BY (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) ASC
                LIMIT 1
            ) as trusted_vendor
        FROM public.products p
        WHERE p.is_active = true 
          AND p.is_popular = true
          AND (p_category_id IS NULL OR p.category_id = p_category_id)
    ) item_data
    WHERE item_data.trusted_vendor IS NOT NULL;

    RETURN COALESCE(result, '[]'::json);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛡️ RESTORE ORDER CANCELLATION
CREATE OR REPLACE FUNCTION public.cancel_order_v2(p_order_id UUID)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.orders 
    SET order_status = 'CANCELLED',
        status = 'CANCELLED',
        updated_at = now()
    WHERE id = p_order_id 
      AND order_status IN ('PLACED', 'PAYMENT_PENDING');

    IF FOUND THEN
        RETURN jsonb_build_object('success', true);
    ELSE
        RETURN jsonb_build_object('success', false, 'error', 'Order cannot be cancelled in its current state');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 🛡️ REPAIR TRACKING VIEW
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1;
CREATE OR REPLACE VIEW public.order_tracking_stabilized_v1 AS
SELECT 
    o.id as order_id,
    o.id,
    o.master_order_id,
    o.customer_id::text,
    o.vendor_id,
    v.name as vendor_name,
    v.image_url as vendor_logo,
    o.items,
    o.total_amount,
    o.order_status as status,
    o.order_status,
    o.created_at,
    o.delivery_address,
    CASE 
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'READY' THEN 'Ready for Pickup'
        WHEN o.order_status = 'PICKED_UP' THEN 'Out for Delivery'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status
    END as status_display
FROM public.orders o
LEFT JOIN public.vendors v ON o.vendor_id = v.id;

-- 5. 🛡️ PERMISSIONS
GRANT EXECUTE ON FUNCTION public.get_popular_items_feed TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cancel_order_v2 TO anon, authenticated, service_role;
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

COMMIT;
-- Trigger schema reload
NOTIFY pgrst, 'reload schema';
