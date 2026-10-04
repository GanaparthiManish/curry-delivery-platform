-- 🛵 MASTER LOGISTICS RESTORATION V14 (RIDER APP STABILITY)
-- 🎯 MISSION: Fix Map blankness, No Orders, and Real-time sync failures.
-- 🛠️ WHY: App expects specific JSON keys ('orders') and View columns ('resolved_pickup_lat').

BEGIN;

-- 1. SYNC IDENTITIES & APPROVALS (Ramesh/Sathish Fix)
-- Ensures riders exist in delivery_riders with their real names from registrations.
INSERT INTO public.delivery_riders (id, name, phone, status, is_approved, is_online, created_at)
SELECT 
    id::uuid, 
    COALESCE(name, 'Elite Rider'), 
    phone, 
    'ONLINE', 
    true, 
    true, 
    now()
FROM public.registrations
WHERE type = 'DELIVERY'
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    is_approved = true,
    status = 'ONLINE',
    is_online = true;

UPDATE public.registrations SET status = 'APPROVED' WHERE type = 'DELIVERY';

-- 2. HARDEN VIEW FOR RIDER MAP (Map Blankness Fix)
-- Adding resolved_pickup_lat/lng columns which the Rider App Map requires.
CREATE OR REPLACE VIEW public.order_details_v3 AS
SELECT 
    o.*,
    COALESCE(o.pickup_lat, v.latitude) as resolved_pickup_lat,
    COALESCE(o.pickup_lng, v.longitude) as resolved_pickup_lng,
    v.name as vendor_name, 
    v.address as vendor_address,
    v.owner_id as vendor_owner_id,
    cp.full_name as customer_name,
    dr.name as rider_name
FROM public.orders o
LEFT JOIN public.vendors v ON o.vendor_id = v.id
LEFT JOIN public.customer_profiles cp ON o.customer_id = cp.id
LEFT JOIN public.delivery_riders dr ON o.rider_id = dr.id;

GRANT SELECT ON public.order_details_v3 TO anon, authenticated, service_role;

-- 3. FIX RIDER DASHBOARD RPC (No Orders Fix)
-- Updated to include the 'orders' key (combined list) that the app logic expects.
CREATE OR REPLACE FUNCTION public.get_rider_dashboard_v2(
    p_rider_auth_id TEXT,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_rider_id UUID;
    v_active_orders JSONB;
    v_available_orders JSONB;
    v_all_orders JSONB;
    v_stats JSONB;
    v_rider_name TEXT;
    v_radius_km DOUBLE PRECISION := 10.0; -- 10KM Limit
BEGIN
    -- 1. Find the rider
    SELECT id, name INTO v_rider_id, v_rider_name 
    FROM public.delivery_riders WHERE id::text = p_rider_auth_id LIMIT 1;
    
    IF v_rider_id IS NULL THEN
        RETURN jsonb_build_object('error', 'RIDER_NOT_FOUND', 'rider_id', p_rider_auth_id);
    END IF;

    -- 2. Active Orders (Assigned to this rider)
    SELECT jsonb_agg(o) INTO v_active_orders FROM (
        SELECT * FROM public.order_details_v3 
        WHERE rider_id = v_rider_id 
        AND status NOT IN ('delivered', 'cancelled', 'rejected', 'completed')
    ) o;

    -- 4. Available Orders (Nearby & Unassigned)
    IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT * FROM public.order_details_v3
            WHERE rider_id IS NULL 
            AND status IN ('placed', 'accepted', 'preparing', 'ready')
            AND (
                6371 * acos(
                    cos(radians(p_lat)) * cos(radians(resolved_pickup_lat)) * 
                    cos(radians(resolved_pickup_lng) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(resolved_pickup_lat))
                )
            ) <= v_radius_km
        ) o;
    ELSE
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT * FROM public.order_details_v3
            WHERE rider_id IS NULL 
            AND status IN ('placed', 'accepted', 'preparing', 'ready')
            LIMIT 10
        ) o;
    END IF;

    -- Combined Orders List for App Compatibility
    v_all_orders := COALESCE(v_active_orders, '[]'::jsonb) || COALESCE(v_available_orders, '[]'::jsonb);

    -- 5. Stats
    SELECT jsonb_build_object(
        'deliveries_count', COUNT(*),
        'today_earnings', COALESCE(SUM(total * 0.1), 0)
    ) INTO v_stats
    FROM public.orders 
    WHERE rider_id = v_rider_id AND status = 'delivered';

    RETURN jsonb_build_object(
        'rider_id', v_rider_id,
        'rider_name', COALESCE(v_rider_name, 'Rider'),
        'orders', v_all_orders, -- THE CRITICAL KEY
        'active_orders', COALESCE(v_active_orders, '[]'::jsonb),
        'available_orders', COALESCE(v_available_orders, '[]'::jsonb),
        'stats', v_stats
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. ENABLE BROAD-SPECTRUM REALTIME
DO $$
BEGIN
    DROP PUBLICATION IF EXISTS supabase_realtime;
    CREATE PUBLICATION supabase_realtime FOR ALL TABLES;
EXCEPTION WHEN OTHERS THEN
    -- Fallback if FOR ALL TABLES is restricted
    ALTER PUBLICATION supabase_realtime ADD TABLE public.orders, public.delivery_riders, public.vendors, public.registrations, public.delivery_live_location;
END $$;

ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.delivery_riders REPLICA IDENTITY FULL;
ALTER TABLE public.delivery_live_location REPLICA IDENTITY FULL;

-- 5. MASTER GPS UPDATE (Rider Side)
-- Fixed: More lenient ID handling to prevent GPS errors.
CREATE OR REPLACE FUNCTION public.update_delivery_location_v16(
    p_order_id TEXT DEFAULT NULL,
    p_rider_id TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_speed DOUBLE PRECISION DEFAULT 0,
    p_heading DOUBLE PRECISION DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
    -- 1. Update Live Location Table (Primary Realtime source)
    INSERT INTO public.delivery_live_location (
        delivery_id, order_id, latitude, longitude, heading, speed, updated_at
    ) VALUES (
        p_rider_id, 
        NULLIF(p_order_id, '')::uuid, 
        p_lat, p_lng, p_heading, p_speed, now()
    )
    ON CONFLICT (delivery_id) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        updated_at = now();

    -- 2. Performance: Update the delivery_rider's general location
    UPDATE public.delivery_riders SET
        last_lat = p_lat,
        last_lng = p_lng,
        last_active_at = now(),
        is_online = true
    WHERE id::text = p_rider_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
NOTIFY pgrst, 'reload schema';
