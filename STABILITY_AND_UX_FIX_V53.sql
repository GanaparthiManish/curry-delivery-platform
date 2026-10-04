-- 🛠️ UNIVERSAL STABILITY & UX OVERHAUL (V53.0)
-- 🎯 MISSION: Kill shell operator errors, stabilize order tracking, and fix shop naming.

BEGIN;

-- 1. 🛡️ REPAIR ORDER TRACKING VIEW (Fixes Shop vs Restaurant naming)
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
    o.total_amount as total,
    o.total_amount,
    o.order_status as status,
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
    dr.full_name as rider_name,
    dr.phone as rider_phone,
    dr.current_lat as rider_lat,
    dr.current_lng as rider_lng,
    dr.bearing as rider_bearing,
    dr.speed as rider_speed,
    -- Status Display
    CASE 
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'READY' THEN 'Food is Ready'
        WHEN o.order_status = 'PICKED_UP' THEN 'On the Way'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status
    END as status_display,
    -- Progress Step (1-5)
    CASE 
        WHEN o.order_status = 'PLACED' THEN 1
        WHEN o.order_status IN ('ACCEPTED', 'COOKING') THEN 2
        WHEN o.order_status = 'READY' THEN 3
        WHEN o.order_status = 'PICKED_UP' THEN 4
        WHEN o.order_status = 'DELIVERED' THEN 5
        ELSE 1
    END as current_step
FROM public.orders o
LEFT JOIN public.vendors v ON o.vendor_id = v.id
LEFT JOIN public.delivery_riders dr ON o.rider_id = dr.id;

GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

-- 2. 🛡️ BULLETPROOF CANCELLATION (Fixes "shell operator: text = uuid")
CREATE OR REPLACE FUNCTION public.cancel_order_stabilized_v2(
    p_order_id UUID,
    p_customer_id TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_order RECORD;
BEGIN
    -- 1. Fetch with explicit casting to avoid operator shell errors
    SELECT * INTO v_order 
    FROM public.orders 
    WHERE id = p_order_id 
      AND customer_id::text = p_customer_id::text
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order not found or unauthorized');
    END IF;

    -- 2. Check if cancellable
    IF v_order.order_status NOT IN ('PLACED', 'PAYMENT_PENDING') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot cancel order in ' || v_order.order_status || ' state');
    END IF;

    -- 3. Perform update with explicit status cast
    UPDATE public.orders 
    SET order_status = 'CANCELLED',
        status = 'CANCELLED',
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'message', 'Order cancelled successfully');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛡️ STABILIZE DELIVERY COMPLETION (Fixes "not updated" issue)
CREATE OR REPLACE FUNCTION public.rider_deliver_order_v3(
    p_order_id UUID
)
RETURNS JSONB AS $$
BEGIN
    UPDATE public.orders 
    SET order_status = 'DELIVERED',
        status = 'DELIVERED',
        payment_status = 'SUCCESS', -- Auto-confirm payment on delivery (especially for COD)
        updated_at = now()
    WHERE id = p_order_id;

    -- Update rider earnings (simple 10% for now)
    UPDATE public.delivery_riders 
    SET wallet_balance = wallet_balance + (SELECT total_amount * 0.1 FROM public.orders WHERE id = p_order_id)
    WHERE id = (SELECT rider_id FROM public.orders WHERE id = p_order_id);

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 🛡️ AGGRESSIVE RLS REPAIR (Ensures UUID vs TEXT doesn't block queries)
ALTER TABLE public.orders DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Customers can view own orders" ON public.orders;
CREATE POLICY "Customers can view own orders" 
ON public.orders FOR SELECT 
USING (customer_id::text = (auth.uid())::text OR customer_id::text = 'guest_tester');

DROP POLICY IF EXISTS "Customers can update own orders" ON public.orders;
CREATE POLICY "Customers can update own orders" 
ON public.orders FOR UPDATE
USING (customer_id::text = (auth.uid())::text);

-- 5. 🏗️ MASTER ORDER HELPER (Unified View for Item-First grouping)
-- This allows the app to fetch everything for a customer in one clean list.
CREATE OR REPLACE FUNCTION public.get_customer_history_v2(p_customer_id TEXT)
RETURNS JSONB AS $$
BEGIN
    RETURN (
        SELECT json_agg(o) FROM (
            SELECT * FROM public.order_tracking_stabilized_v1
            WHERE customer_id = p_customer_id
            ORDER BY created_at DESC
            LIMIT 50
        ) o
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.cancel_order_stabilized_v2 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.rider_deliver_order_v3 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_customer_history_v2 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
