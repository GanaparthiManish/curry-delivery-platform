-- 🛡️ TRACKING & REALTIME NOTIFICATION FIX
-- 🎯 MISSION: Enforce accurate vendor coordinates during order placement & real-time notification sync.

BEGIN;

-- 1. Ensure Real-time Publications exist for both Orders and Notifications
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'orders') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notifications') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'delivery_riders') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_riders;
    END IF;
END $$;

-- 2. Drop place_order_v4 to recreate it cleanly
DROP FUNCTION IF EXISTS public.place_order_v4(TEXT, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT) CASCADE;

-- 3. Recreate place_order_v4 with correct vendor_lat and vendor_lng storage
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
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
    v_vendor_id_text TEXT;
BEGIN
    v_master_id := gen_random_uuid()::TEXT;

    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        v_vendor_id_text := (v_sub_order->>'vendor_id')::TEXT;
        
        -- Get Vendor Location
        SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng 
        FROM public.vendors WHERE id::text = v_vendor_id_text::text;

        -- Calculate Distance
        v_dist := (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v_vendor_lat)) * cos(radians(v_vendor_lng) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v_vendor_lat))
                  ))));

        -- Proximity Warning or Strict check can be adjusted here if needed (15km limit for safety)
        IF v_dist > 15.0 THEN
            RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Your location is % km away from Vendor (Limit: 15km).', ROUND(v_dist::numeric, 2);
        END IF;

        -- 🛡️ Insert including vendor_lat and vendor_lng
        INSERT INTO public.orders (
            master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            vendor_lat, vendor_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions, created_at
        ) VALUES (
            v_master_id,
            p_customer_id::text,
            v_vendor_id_text::text,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            v_vendor_lat,
            v_vendor_lng,
            'PLACED',
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions,
            now()
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.place_order_v4 TO anon, authenticated, service_role;

-- 4. Recreate the order tracking view to always fallback to the vendors table coordinates if order's vendor coordinates are missing
CREATE OR REPLACE VIEW public.order_tracking_stabilized_v1 AS
SELECT 
    o.id AS order_id,
    o.id AS id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    o.order_status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    COALESCE(o.delivery_address, 'Address not found') as delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    COALESCE(o.vendor_lat, v.latitude) AS vendor_lat,
    COALESCE(o.vendor_lng, v.longitude) AS vendor_lng,
    o.rider_lat,
    o.rider_lng,
    o.items,
    o.created_at,
    o.updated_at,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Payment Pending'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'PICKED_UP' THEN 'Out for Delivery'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status 
    END AS status_display,
    CASE 
        WHEN o.order_status = 'PLACED' THEN 1
        WHEN o.order_status = 'ACCEPTED' THEN 2
        WHEN o.order_status = 'COOKING' THEN 3
        WHEN o.order_status = 'PICKED_UP' THEN 4
        WHEN o.order_status = 'DELIVERED' THEN 5
        ELSE 1
    END AS current_step,
    v.name AS vendor_name,
    v.image_url AS vendor_image,
    v.logo_url AS vendor_logo,
    v.phone AS vendor_phone,
    v.address AS vendor_address,
    r.name AS rider_name,
    r.phone AS rider_phone,
    COALESCE(r.avatar_url, r.profile_image) AS rider_avatar,
    r.rating AS rider_rating,
    r.vehicle_number AS rider_vehicle
FROM orders o
LEFT JOIN vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN delivery_riders r ON (o.rider_id::text) = (r.id::text);

GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
SELECT 'TRACKING AND REALTIME FIXED!' as status;
