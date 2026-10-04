-- 🛵 RIDER LOGISTICS & NEARBY ORDER OPTIMIZATION (v2.0)
-- Purpose: Implement location-based order fetching, atomic assignment, and heartbeat sync with Admin/Customer compatibility.

-- 1. 🛰️ GPS HEARTBEAT SYNC
-- Updates both core table and live tracking table used by Admin/Customer maps.
DROP FUNCTION IF EXISTS rider_update_gps_v1(uuid, double precision, double precision, double precision, double precision);
CREATE OR REPLACE FUNCTION rider_update_gps_v1(
    p_rider_auth_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_bearing DOUBLE PRECISION DEFAULT 0,
    p_speed DOUBLE PRECISION DEFAULT 0
)
RETURNS BOOLEAN AS $$
DECLARE
    v_order_id UUID;
BEGIN
    -- 1. Update Core Delivery Rider Table
    UPDATE public.delivery_riders
    SET 
        current_lat = p_lat,
        current_lng = p_lng,
        last_gps_update = now(),
        status = CASE WHEN status = 'OFFLINE' THEN 'ONLINE' ELSE status END,
        updated_at = now()
    WHERE id = p_rider_auth_id;

    -- 2. Fetch Active Order ID if any
    SELECT active_order_id INTO v_order_id FROM public.delivery_riders WHERE id = p_rider_auth_id;

    -- 3. Update Live Location Table (Used by Admin MissionMap and Customer Tracking)
    INSERT INTO public.delivery_live_location (rider_id, order_id, latitude, longitude, heading, speed, updated_at)
    VALUES (p_rider_auth_id, v_order_id, p_lat, p_lng, p_bearing, p_speed, now())
    ON CONFLICT (rider_id) DO UPDATE SET
        order_id = EXCLUDED.order_id,
        latitude = EXCLUDED.latitude,
        longitude = EXCLUDED.longitude,
        heading = EXCLUDED.heading,
        speed = EXCLUDED.speed,
        updated_at = now();

    -- 4. Sync current pos to order for fast rendering in Customer App
    IF v_order_id IS NOT NULL THEN
        UPDATE public.orders
        SET 
            delivery_lat = p_lat,
            delivery_lng = p_lng
        WHERE id = v_order_id;
    END IF;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 📝 ROBUST ORDER ACCEPTANCE RPC
-- Ensures atomic assignment and status updates. Overrides previous simple versions.
DROP FUNCTION IF EXISTS accept_order_v1(uuid, uuid);
CREATE OR REPLACE FUNCTION accept_order_v1(
    p_order_id UUID,
    p_rider_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_order_status TEXT;
BEGIN
    -- 1. Check if order is still available
    SELECT status INTO v_order_status FROM public.orders WHERE id = p_order_id FOR UPDATE;
    
    IF v_order_status IN ('CANCELLED', 'REJECTED') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order no longer available (Cancelled/Rejected)');
    END IF;
    
    IF EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id AND rider_id IS NOT NULL) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order already assigned to another logistics unit');
    END IF;

    -- 2. Atomic Assignment
    UPDATE public.orders 
    SET 
        rider_id = p_rider_id,
        status = 'RIDER_ASSIGNED',
        assigned_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 3. Mark Rider as Busy and Link Order
    UPDATE public.delivery_riders
    SET 
        status = 'BUSY',
        active_order_id = p_order_id,
        updated_at = NOW()
    WHERE id = p_rider_id;

    -- 4. Notify Customer
    INSERT INTO public.notifications (user_id, title, message, event_type)
    SELECT customer_id, 'Rider Assigned', 'A rider is heading to the station to pick up your order.', 'RIDER_ASSIGNED'
    FROM public.orders WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'message', 'Logistics Link Established');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛵 UPGRADED RIDER DASHBOARD RPC (Location-Aware)
DROP FUNCTION IF EXISTS get_rider_dashboard_v2(uuid, double precision, double precision);
CREATE OR REPLACE FUNCTION get_rider_dashboard_v2(
    p_rider_auth_id UUID,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_rider_id UUID;
    v_active_orders JSONB;
    v_available_orders JSONB;
    v_stats JSONB;
    v_radius_km DOUBLE PRECISION := 10.0;
BEGIN
    SELECT id INTO v_rider_id FROM public.delivery_riders WHERE id = p_rider_auth_id LIMIT 1;
    
    IF v_rider_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Rider identity not found in logistics grid');
    END IF;

    -- Approve Rider if they are in the grid (Dev convenience)
    UPDATE public.delivery_riders SET is_approved = true WHERE id = v_rider_id AND is_approved = false;

    -- My Active Missions
    SELECT jsonb_agg(o) INTO v_active_orders FROM (
        SELECT 
            o.id as order_id, 
            o.customer_id, 
            o.vendor_id, 
            v.name as vendor_name,
            v.address as vendor_address,
            v.latitude as resolved_pickup_lat,
            v.longitude as resolved_pickup_lng,
            o.items, 
            o.total, 
            o.status, 
            o.address as effective_address, 
            o.delivery_lat, 
            o.delivery_lng,
            CASE 
                WHEN o.status = 'RIDER_ASSIGNED' THEN 'Proceed to Restaurant'
                WHEN o.status = 'ACCEPTED' THEN 'Heading to Station'
                WHEN o.status = 'PREPARING' THEN 'Chef is Cooking'
                WHEN o.status = 'READY' THEN 'Food Ready for Pickup'
                WHEN o.status = 'PICKED_UP' THEN 'Food Picked Up'
                WHEN o.status = 'ON_THE_WAY' THEN 'Out for Delivery'
                ELSE o.status
            END as status_display
        FROM public.orders o
        JOIN public.vendors v ON o.vendor_id = v.id
        WHERE o.rider_id = v_rider_id 
          AND o.status NOT IN ('DELIVERED', 'CANCELLED', 'REJECTED', 'COMPLETED')
    ) o;

    -- Available Missions (Nearby scanning)
    IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT 
                o.id as order_id, 
                v.name as vendor_name, 
                v.address as vendor_address,
                o.total, 
                o.status, 
                (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) AS distance_km
            FROM public.orders o
            JOIN public.vendors v ON o.vendor_id = v.id
            WHERE o.status IN ('READY_FOR_PICKUP', 'ACCEPTED', 'PLACED', 'READY', 'PREPARING')
              AND o.rider_id IS NULL
              AND (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) <= v_radius_km
            ORDER BY distance_km ASC
            LIMIT 20
        ) o;
    ELSE
        -- Fallback if no GPS (Legacy mode)
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT o.id as order_id, v.name as vendor_name, o.total, o.status, 0 as distance_km
            FROM public.orders o
            JOIN public.vendors v ON o.vendor_id = v.id
            WHERE o.status IN ('READY_FOR_PICKUP', 'ACCEPTED', 'PLACED', 'READY') AND o.rider_id IS NULL
            LIMIT 20
        ) o;
    END IF;

    -- Fleet Stats
    SELECT jsonb_build_object(
        'deliveries_count', COUNT(*),
        'today_earnings', COALESCE(SUM(total * 0.1), 0)
    ) INTO v_stats
    FROM public.orders 
    WHERE rider_id = v_rider_id AND status = 'DELIVERED';

    RETURN jsonb_build_object(
        'rider_id', v_rider_id,
        'active_orders', COALESCE(v_active_orders, '[]'::jsonb),
        'available_orders', COALESCE(v_available_orders, '[]'::jsonb),
        'orders', COALESCE(v_active_orders, '[]'::jsonb) || COALESCE(v_available_orders, '[]'::jsonb),
        'stats', v_stats
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 🧹 STALE DATA RECOVERY (Logistics Healing)
UPDATE public.delivery_riders SET status = 'ONLINE' WHERE status = 'BUSY' AND active_order_id IS NULL;
UPDATE public.delivery_riders SET is_online = true WHERE status IN ('ONLINE', 'BUSY');

-- ✅ DONE: These functions bridge the gap between Admin, Rider, and Customer apps.
