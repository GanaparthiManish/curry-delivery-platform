-- 🛰️ ULTIMATE TRACKING SYNC (V43.0)
-- 🎯 MISSION: Sync all tracking columns across all tables to ensure Customer App moves.

BEGIN;

-- 1. 🏗️ ENSURE COLUMNS EXIST (Redundancy for stability)
ALTER TABLE public.delivery_riders 
ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS last_lat DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS last_lng DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS bearing DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS speed DOUBLE PRECISION DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_gps_update TIMESTAMPTZ DEFAULT now();

-- 2. ⚡ THE MASTER SYNC RPC
-- This function updates EVERY possible tracking column to ensure no app is left behind.
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
    -- A. Update the Rider's primary record (The source of truth for the Map)
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

    -- B. Update the Active Order (if any) for the Snapshot Views
    IF p_order_id IS NOT NULL THEN
        UPDATE public.orders SET
            rider_lat = p_lat,
            rider_lng = p_lng,
            updated_at = now()
        WHERE id = p_order_id;
        
        -- C. Insert into history table for route trailing (optional but good)
        INSERT INTO public.order_live_tracking (order_id, rider_id, rider_lat, rider_lng, speed, heading)
        VALUES (p_order_id, p_rider_id::uuid, p_lat, p_lng, p_speed, p_heading);
    END IF;

    -- D. Update Legacy Table (delivery_live_location) just in case old versions are running
    INSERT INTO public.delivery_live_location (
        delivery_id, order_id, latitude, longitude, heading, speed, updated_at
    ) VALUES (
        p_rider_id, p_order_id, p_lat, p_lng, p_heading, p_speed, now()
    )
    ON CONFLICT (delivery_id) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        updated_at = now();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🔗 STABILIZE THE VIEW
-- We change the view to pull rider location DIRECTLY from the rider table if available.
-- This ensures that even if the 'orders' table update is slightly delayed, the map is LIVE.
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;
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
    o.item_total,
    o.delivery_fee,
    o.platform_fee,
    o.gst,
    o.tip_amount,
    COALESCE(o.delivery_address, 'Address not found') as delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.vendor_lat,
    o.vendor_lng,
    -- 🚀 JET ENGINE: Pull live coords from rider table if possible, fallback to order snapshot
    COALESCE(r.current_lat, o.rider_lat) as rider_lat,
    COALESCE(r.current_lng, o.rider_lng) as rider_lng,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions,
    o.delivery_phone as customer_phone,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'PICKED_UP' THEN 'Out for Delivery'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status 
    END AS status_display,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 1
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
    r.avatar_url AS rider_avatar,
    r.rating AS rider_rating,
    r.vehicle_details AS rider_vehicle,
    r.speed as rider_speed,
    r.bearing as rider_bearing
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- 4. 🔓 PERMISSIONS
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
