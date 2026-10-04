-- 🛡️ PRIVACY & ISOLATION MASTER FIX (V46.0)
-- 🎯 MISSION: Stop data leakage between users and fix cancellation failures.
-- 🚀 TARGET: order_tracking_stabilized_v1 (The View that was leaking data)

BEGIN;

-- 1. 🛡️ ENABLE RLS ON ALL CORE TABLES
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_profiles ENABLE ROW LEVEL SECURITY;

-- 2. 🛡️ DROP WEAK POLICIES
DROP POLICY IF EXISTS "Customers can see their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Strict_Customer_Isolation" ON public.orders;
DROP POLICY IF EXISTS "Strict_Rider_Isolation" ON public.orders;
DROP POLICY IF EXISTS "Strict_Vendor_Isolation" ON public.orders;
DROP POLICY IF EXISTS "Nuclear_Orders_Isolation" ON public.orders;
DROP POLICY IF EXISTS "Customers can select own orders" ON public.orders;
DROP POLICY IF EXISTS "Riders can see ready orders" ON public.orders;
DROP POLICY IF EXISTS "Riders can manage assigned orders" ON public.orders;
DROP POLICY IF EXISTS "Vendors can manage restaurant orders" ON public.orders;

-- 3. 🛡️ IMPLEMENT ROBUST ISOLATION

-- A. CUSTOMER ISOLATION (Orders)
-- Handles both UUID and legacy sms_auth_ IDs
CREATE POLICY "Orders_Customer_Policy" ON public.orders
FOR SELECT TO authenticated
USING (
    customer_id::text = auth.uid()::text 
    OR customer_id::text = 'sms_auth_' || (SELECT phone FROM public.customer_profiles WHERE id::text = auth.uid()::text LIMIT 1)
);

-- B. RIDER ISOLATION (Orders)
-- Riders can see assigned orders OR unassigned READY orders
CREATE POLICY "Orders_Rider_Policy" ON public.orders
FOR SELECT TO authenticated
USING (
    rider_id::text = auth.uid()::text
    OR (
        EXISTS (SELECT 1 FROM public.delivery_riders WHERE id::text = auth.uid()::text)
        AND order_status IN ('READY', 'ACCEPTED', 'PLACED')
        AND rider_id IS NULL
    )
);

-- C. VENDOR ISOLATION (Orders)
CREATE POLICY "Orders_Vendor_Policy" ON public.orders
FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.vendors v 
        WHERE v.id::text = public.orders.vendor_id::text 
        AND v.owner_id::text = auth.uid()::text
    )
);

-- D. NOTIFICATION ISOLATION
CREATE POLICY "Notifications_Strict_Policy" ON public.notifications
FOR SELECT TO authenticated
USING (
    user_id::text = auth.uid()::text 
    OR user_id::text = 'sms_auth_' || (SELECT phone FROM public.customer_profiles WHERE id::text = auth.uid()::text LIMIT 1)
    OR user_id = 'BROADCAST'
);

-- 4. 🛡️ VIEW REPAIR: THE MAGIC BULLET
-- We MUST use security_invoker = true so the view respects the policies above.
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;

CREATE VIEW public.order_tracking_stabilized_v1 
WITH (security_invoker = true) AS
SELECT
    o.id AS order_id,
    o.id AS id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    COALESCE(o.order_status, o.status, 'PLACED') AS order_status,
    COALESCE(o.status, o.order_status, 'PLACED')  AS status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    o.item_total,
    o.delivery_fee,
    o.platform_fee,
    o.gst,
    o.tip_amount,
    COALESCE(o.delivery_address, 'Address not found') AS delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.vendor_lat,
    o.vendor_lng,
    o.rider_lat,
    o.rider_lng,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions,
    o.delivery_phone AS customer_phone,
    o.delivery_pincode,
    o.delivery_house_number,
    v.name AS vendor_name,
    v.image_url AS vendor_image,
    r.name AS rider_name,
    r.phone AS rider_phone,
    CASE 
        WHEN COALESCE(o.order_status, o.status) = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN COALESCE(o.order_status, o.status) = 'PLACED'          THEN 'Order Placed'
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED'        THEN 'Preparing'
        WHEN COALESCE(o.order_status, o.status) = 'COOKING'         THEN 'Cooking'
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP'       THEN 'Out for Delivery'
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED'       THEN 'Delivered'
        WHEN COALESCE(o.order_status, o.status) = 'CANCELLED'       THEN 'Cancelled'
        ELSE COALESCE(o.order_status, o.status, 'Unknown')
    END AS status_display
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- 5. 🛡️ RPC REPAIR: CANCELLATION & STATUS
-- We drop all potential versions to avoid "function not unique" errors.
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_order_status_v3(TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_order_status_v3(TEXT, TEXT) CASCADE;

CREATE OR REPLACE FUNCTION public.update_order_status_v3(
    p_order_id UUID,
    p_new_status TEXT,
    p_actor_id TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE public.orders SET
        status = UPPER(p_new_status),
        order_status = UPPER(p_new_status),
        updated_at = NOW()
    WHERE id = p_order_id;
    
    -- Cleanup rider if cancelled
    IF UPPER(p_new_status) IN ('CANCELLED', 'REJECTED') THEN
        UPDATE public.delivery_riders 
        SET active_order_id = NULL 
        WHERE active_order_id = p_order_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. PERMISSIONS
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_order_status_v3 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
SELECT 'Privacy Isolation Hotfix V46.0 Applied!' as result;
