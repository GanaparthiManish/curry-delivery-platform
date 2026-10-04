-- 🛵 RIDER VISIBILITY FIX V12.1 (STRICT 10KM)
-- 🎯 MISSION: Restore 10km rider radius while fixing the "invisible order" bug.

BEGIN;

-- 1. DROP PREVIOUS HELPER TO ENSURE CLEAN OVERWRITE
DROP FUNCTION IF EXISTS get_rider_dashboard_v2(uuid, double precision, double precision) CASCADE;

-- 2. CREATE THE BULLETPROOF RIDER DASHBOARD
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
    v_rider_name TEXT;
    v_radius_km DOUBLE PRECISION := 10.0; -- AS REQUESTED: 10KM LIMIT
BEGIN
    -- 1. Find the rider in the system
    SELECT id INTO v_rider_id FROM public.delivery_riders WHERE id = p_rider_auth_id LIMIT 1;
    
    IF v_rider_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Rider identity not found in logistics grid');
    END IF;

    -- 2. Auto-fix permissions (Ensures you can work)
    UPDATE public.delivery_riders 
    SET is_approved = true, is_online = true, status = 'ONLINE' 
    WHERE id = v_rider_id AND (is_approved = false OR is_online = false);

    -- 3. FETCH ACTIVE ORDERS (Missions you already accepted)
    SELECT jsonb_agg(o) INTO v_active_orders FROM (
        SELECT 
            o.id::text as order_id, 
            o.vendor_id::text, 
            v.name::text as vendor_name,
            v.address::text as vendor_address,
            v.latitude::double precision as resolved_pickup_lat,
            v.longitude::double precision as resolved_pickup_lng,
            o.items, o.total, o.status, 
            o.address::text as effective_address, 
            o.delivery_lat, o.delivery_lng,
            COALESCE(o.order_status, o.status)::text as status_display
        FROM public.orders o
        JOIN public.vendors v ON (o.vendor_id::uuid) = v.id
        WHERE o.rider_id = v_rider_id 
          AND o.status NOT IN ('DELIVERED', 'CANCELLED', 'REJECTED', 'COMPLETED')
    ) o;

    -- 4. FETCH AVAILABLE ORDERS (The ones you see in the pool)
    -- This uses the 10km radius if GPS is available.
    IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT 
                o.id::text as order_id, 
                v.name::text as vendor_name, 
                v.address::text as vendor_address,
                o.total, o.status, 
                (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))))) AS distance_km
            FROM public.orders o
            JOIN public.vendors v ON (o.vendor_id::uuid) = v.id
            WHERE o.status IN ('PLACED', 'ACCEPTED', 'READY', 'PREPARING', 'READY_FOR_PICKUP')
              AND o.rider_id IS NULL
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))))) <= v_radius_km
            ORDER BY distance_km ASC
            LIMIT 20
        ) o;
    ELSE
        -- Fallback if no GPS (Show everything nearby available)
        SELECT jsonb_agg(o) INTO v_available_orders FROM (
            SELECT o.id::text as order_id, v.name::text as vendor_name, o.total, o.status, 0 as distance_km
            FROM public.orders o
            JOIN public.vendors v ON (o.vendor_id::uuid) = v.id
            WHERE o.status IN ('PLACED', 'ACCEPTED', 'READY', 'PREPARING', 'READY_FOR_PICKUP') 
              AND o.rider_id IS NULL
            LIMIT 20
        ) o;
    END IF;

    -- 5. Fleet Stats & Identity
    SELECT 
        jsonb_build_object(
            'deliveries_count', COUNT(*),
            'today_earnings', COALESCE(SUM(total * 0.1), 0)
        ),
        (SELECT name FROM public.delivery_riders WHERE id = v_rider_id)
    INTO v_stats, v_rider_name
    FROM public.orders 
    WHERE rider_id = v_rider_id AND status = 'DELIVERED';

    RETURN jsonb_build_object(
        'rider_id', v_rider_id,
        'rider_name', COALESCE(v_rider_name, 'ELITE RIDER'),
        'active_orders', COALESCE(v_active_orders, '[]'::jsonb),
        'available_orders', COALESCE(v_available_orders, '[]'::jsonb),
        'stats', v_stats
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
