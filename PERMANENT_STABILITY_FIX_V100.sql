-- 🛡️ ULTIMATE STABILITY & PRIVACY FIX (V100)
-- 🎯 MISSION: Permanent fix for "UPI Pending" and "Random Orders" leak.
-- 🚀 TARGET: Customer isolation and reliable payment confirmation.

BEGIN;

-- 1. 🛠️ THE MASTER PAYMENT CONFIRMER
-- This handles master_order_ids from place_order_v4
CREATE OR REPLACE FUNCTION public.confirm_master_payment_v4(p_master_id TEXT, p_payment_id TEXT)
RETURNS void AS $$
BEGIN
    UPDATE public.orders
    SET status = 'PLACED',
        order_status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = NOW()
    WHERE master_order_id = p_master_id;
    
    -- Also update any single order that might have this as its primary ID
    UPDATE public.orders
    SET status = 'PLACED',
        order_status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = NOW()
    WHERE id::text = p_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 🛡️ RE-ENFORCE STRICT ISOLATION (Privacy)
-- This stops users from seeing "random orders"
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Drop all old potentially leaky policies
DROP POLICY IF EXISTS "Orders_Customer_Policy" ON public.orders;
DROP POLICY IF EXISTS "Users see only their orders" ON public.orders;
DROP POLICY IF EXISTS "Allow all orders" ON public.orders;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.orders;

-- New Strict Policy: Matches by exact customer_id (UUID or sms_auth_)
CREATE POLICY "Strict_Customer_Order_Isolation" ON public.orders
FOR SELECT TO authenticated
USING (
    customer_id::text = auth.uid()::text 
    OR customer_id::text = 'sms_auth_' || (SELECT phone FROM public.customer_profiles WHERE id::text = auth.uid()::text LIMIT 1)
);

-- 3. 🛡️ VIEW REPAIR
-- Ensure the view respects RLS
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;
CREATE VIEW public.order_tracking_stabilized_v1 
WITH (security_invoker = true) AS
SELECT
    o.id AS order_id,
    o.id AS id,
    o.master_order_id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    COALESCE(o.order_status, o.status, 'PLACED') AS order_status,
    COALESCE(o.status, o.order_status, 'PLACED')  AS status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    o.delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.items,
    o.created_at,
    o.updated_at,
    o.delivery_phone,
    v.name AS vendor_name,
    v.image_url AS vendor_image,
    r.name AS rider_name,
    r.phone AS rider_phone
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- 4. PERMISSIONS
GRANT EXECUTE ON FUNCTION public.confirm_master_payment_v4 TO anon, authenticated, service_role;
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
