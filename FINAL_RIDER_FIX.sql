-- ═══════════════════════════════════════════════════════════════
-- FINAL RIDER VISIBILITY FIX (v4 - STABLE LOCATION AWARE)
-- ═══════════════════════════════════════════════════════════════

BEGIN;

-- 1. RLS FIX: Allow riders to see unassigned orders
DROP POLICY IF EXISTS "riders_view_unassigned" ON public.orders;
CREATE POLICY "riders_view_unassigned" ON public.orders
    FOR SELECT
    TO authenticated
    USING (true);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- 2. Drop all overloads (CRITICAL: specifying types exactly)
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(uuid, double precision, double precision);
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(text, double precision, double precision);
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(uuid);
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(text);
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(uuid, numeric, numeric);
DROP FUNCTION IF EXISTS public.get_rider_dashboard_v2(text, numeric, numeric);

-- 3. Create the Stable Location-Aware version
CREATE OR REPLACE FUNCTION public.get_rider_dashboard_v2(
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
BEGIN
    -- Resolve rider
    SELECT id INTO v_rider_id 
    FROM public.delivery_riders 
    WHERE id::text = p_rider_auth_id::text 
    LIMIT 1;
    
    IF v_rider_id IS NULL THEN
        v_rider_id := p_rider_auth_id;
    END IF;

    -- A. My active orders
    SELECT jsonb_agg(row_to_json(o)) INTO v_active_orders FROM (
        SELECT 
            o.id,
            COALESCE(v.name, 'Restaurant') as vendor_name,
            COALESCE(v.address, '') as vendor_address,
            COALESCE(v.latitude, o.pickup_lat) as resolved_pickup_lat,
            COALESCE(v.longitude, o.pickup_lng) as resolved_pickup_lng,
            o.items,
            COALESCE(o.total_amount, o.total, 0) as total,
            COALESCE(o.delivery_fee, 50) as earnings,
            COALESCE(o.order_status, o.status) as status,
            o.delivery_address,
            o.delivery_lat,
            o.delivery_lng,
            o.payment_method,
            o.created_at,
            COALESCE(c.full_name, 'Customer') as customer_name,
            c.phone as customer_phone
        FROM public.orders o
        LEFT JOIN public.vendors v ON v.id::text = o.vendor_id::text
        LEFT JOIN public.customer_profiles c ON c.id::text = o.customer_id::text
        WHERE o.rider_id::text = v_rider_id::text
          AND UPPER(COALESCE(o.order_status, o.status)) NOT IN ('DELIVERED','CANCELLED','REJECTED','COMPLETED')
        ORDER BY o.created_at DESC
        LIMIT 5
    ) o;

    -- B. Available unassigned orders (15km Filter)
    SELECT jsonb_agg(row_to_json(avail)) INTO v_available_orders FROM (
        SELECT 
            o.id,
            COALESCE(v.name, 'Restaurant') as vendor_name,
            COALESCE(v.address, o.delivery_address, '') as vendor_address,
            COALESCE(o.total_amount, o.total, 0) as total,
            COALESCE(o.delivery_fee, 50) as earnings,
            COALESCE(o.order_status, o.status) as status,
            COALESCE(v.latitude, o.pickup_lat) as shop_lat,
            COALESCE(v.longitude, o.pickup_lng) as shop_lng,
            o.delivery_lat,
            o.delivery_lng,
            o.payment_method,
            o.items,
            o.created_at,
            CASE 
                WHEN p_lat IS NOT NULL AND p_lat != 0 
                     AND COALESCE(v.latitude, o.pickup_lat) IS NOT NULL
                THEN (6371 * acos(LEAST(1.0, GREATEST(-1.0,
                    cos(radians(p_lat)) * 
                    cos(radians(COALESCE(v.latitude, o.pickup_lat))) * 
                    cos(radians(COALESCE(v.longitude, o.pickup_lng)) - radians(p_lng)) + 
                    sin(radians(p_lat)) * 
                    sin(radians(COALESCE(v.latitude, o.pickup_lat)))
                ))))
                ELSE 0
            END as distance_km
        FROM public.orders o
        LEFT JOIN public.vendors v ON v.id::text = o.vendor_id::text
        WHERE (o.rider_id IS NULL OR o.rider_id::text = '')
          AND UPPER(COALESCE(o.order_status, o.status)) IN (
              'PLACED','ACCEPTED','PREPARING','READY',
              'READY_FOR_PICKUP','COOKING','ASSIGNED','RIDER_ASSIGNED'
          )
          -- 15km filter
          AND (
            p_lat IS NULL OR p_lat = 0
            OR (6371 * acos(LEAST(1.0, GREATEST(-1.0,
                cos(radians(p_lat)) * 
                cos(radians(COALESCE(v.latitude, o.pickup_lat, p_lat))) * 
                cos(radians(COALESCE(v.longitude, o.pickup_lng, p_lng)) - radians(p_lng)) + 
                sin(radians(p_lat)) * 
                sin(radians(COALESCE(v.latitude, o.pickup_lat, p_lat)))
            )))) <= 15.0
          )
        ORDER BY o.created_at DESC
        LIMIT 50
    ) avail;

    -- C. Stats
    SELECT jsonb_build_object(
        'deliveries_count', COUNT(*),
        'total_earnings', COALESCE(SUM(delivery_fee), 0),
        'rider_id', v_rider_id
    ) INTO v_stats
    FROM public.orders
    WHERE rider_id::text = v_rider_id::text
      AND UPPER(COALESCE(order_status, status)) IN ('DELIVERED','COMPLETED');

    RETURN jsonb_build_object(
        'active_orders',    COALESCE(v_active_orders, '[]'::jsonb),
        'available_orders', COALESCE(v_available_orders, '[]'::jsonb),
        'stats',            COALESCE(v_stats, '{}'::jsonb)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_rider_dashboard_v2 TO authenticated, anon;
GRANT SELECT ON public.orders TO authenticated;
GRANT SELECT ON public.vendors TO authenticated;
GRANT SELECT ON public.customer_profiles TO authenticated;

COMMIT;
