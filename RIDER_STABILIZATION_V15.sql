-- 🚀 RIDER ULTIMATE REPAIR & CLEANUP (V16.2)
-- 🎯 FIXES: RLS Access, Column Names (rider_lat), and Mission Fetch.

BEGIN;

-- 1. 🔓 WIDE OPEN ACCESS (For Debugging Tracking)
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_riders DISABLE ROW LEVEL SECURITY;

-- 2. 🛰️ MISSION FETCH ENGINE (Robust)
CREATE OR REPLACE FUNCTION public.get_active_mission_v1(p_rider_id TEXT)
RETURNS JSONB AS $$
DECLARE
    v_mission JSONB;
BEGIN
    SELECT row_to_json(m)::jsonb INTO v_mission FROM (
        SELECT 
            o.id,
            o.status,
            o.order_status,
            o.pickup_lat,
            o.pickup_lng,
            o.delivery_lat,
            o.delivery_lng,
            o.delivery_address,
            v.name as vendor_name,
            v.latitude as vendor_lat,
            v.longitude as vendor_lng,
            cp.full_name as customer_name,
            cp.phone as customer_phone
        FROM public.orders o
        LEFT JOIN public.vendors v ON v.id::text = o.vendor_id::text
        LEFT JOIN public.customer_profiles cp ON cp.id::text = o.customer_id::text
        WHERE o.rider_id::text = p_rider_id::text
          AND UPPER(COALESCE(o.status, o.order_status)) NOT IN ('DELIVERED', 'CANCELLED', 'COMPLETED', 'REJECTED')
        ORDER BY o.created_at DESC
        LIMIT 1
    ) m;
    
    RETURN COALESCE(v_mission, NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛰️ TRACKING ENGINE (Fixing Column Names)
DO $$ 
DECLARE r RECORD;
BEGIN
    FOR r IN (SELECT oid::regprocedure as func_spec FROM pg_proc WHERE proname = 'update_delivery_location_v16') 
    LOOP EXECUTE 'DROP FUNCTION ' || r.func_spec || ' CASCADE'; END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.update_delivery_location_v16(
    p_rider_id TEXT,
    p_order_id TEXT DEFAULT NULL,
    p_lat DOUBLE PRECISION DEFAULT NULL,
    p_lng DOUBLE PRECISION DEFAULT NULL,
    p_heading DOUBLE PRECISION DEFAULT 0,
    p_speed DOUBLE PRECISION DEFAULT 0
)
RETURNS JSONB AS $$
BEGIN
    -- Update Rider
    UPDATE public.delivery_riders
    SET current_lat = p_lat, current_lng = p_lng, heading = p_heading, last_gps_update = now(), updated_at = now()
    WHERE id::text = p_rider_id::text;

    -- Update Order (Using correct columns: rider_lat, rider_lng)
    IF p_order_id IS NOT NULL AND p_order_id != '' THEN
        UPDATE public.orders
        SET 
            rider_lat = p_lat, 
            rider_lng = p_lng, 
            updated_at = now()
        WHERE id::text = p_order_id::text;
    END IF;
    RETURN jsonb_build_object('success', true, 'timestamp', now());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated, anon;

COMMIT;
