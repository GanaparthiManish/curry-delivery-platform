-- 🛡️ FINAL ORDER STABILITY & RLS MASTER FIX (V49.0)
-- 🎯 MISSION: Kill the "operator is only a shell: text = uuid" error for good.

BEGIN;

-- 1. 🛡️ CLEAN SLATE: DROP ALL POLICIES ON ORDERS
-- This ensures no ghost policies from previous versions are causing type mismatches.
DO $$ 
DECLARE 
    pol record;
BEGIN 
    FOR pol IN (SELECT policyname FROM pg_policies WHERE tablename = 'orders' AND schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.orders', pol.policyname);
    END LOOP;
END $$;

-- 2. 🏗️ RE-ENABLE RLS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- 3. 🛡️ CREATE ROBUST CAST-SAFE POLICIES
-- We use ::text everywhere to ensure no "shell operator" errors during comparison.

-- A. Customer Access (Supports both UUID and sms_auth strings)
CREATE POLICY "Orders_Customer_Access_V49" ON public.orders
FOR ALL TO authenticated
USING (
    customer_id::text = auth.uid()::text 
    OR customer_id::text = 'sms_auth_' || (SELECT phone FROM public.customer_profiles WHERE id::text = auth.uid()::text LIMIT 1)
)
WITH CHECK (
    customer_id::text = auth.uid()::text 
    OR customer_id::text = 'sms_auth_' || (SELECT phone FROM public.customer_profiles WHERE id::text = auth.uid()::text LIMIT 1)
);

-- B. Rider Access
CREATE POLICY "Orders_Rider_Access_V49" ON public.orders
FOR ALL TO authenticated
USING (
    rider_id::text = auth.uid()::text 
    OR status IN ('PLACED', 'READY', 'ACCEPTED')
);

-- C. Vendor Access
CREATE POLICY "Orders_Vendor_Access_V49" ON public.orders
FOR ALL TO authenticated
USING (
    vendor_id::text IN (SELECT id::text FROM public.vendors WHERE user_id::text = auth.uid()::text)
);

-- 4. 🛡️ FIX NOTIFICATION TRIGGER (UUID Mismatch Protection)
-- Prevents trigger failures from crashing the order update.
CREATE OR REPLACE FUNCTION handle_core_notifications_v3()
RETURNS TRIGGER AS $$
DECLARE
    v_customer_uuid uuid;
BEGIN
    -- Try to cast customer_id to UUID safely
    BEGIN
        v_customer_uuid := NEW.customer_id::uuid;
        
        IF (TG_OP = 'INSERT') THEN
            INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
            VALUES (v_customer_uuid, 'customer', 'Order Confirmed 🎉', 'Your order has been placed successfully.', NEW.id, 'order');
        END IF;

        IF (TG_OP = 'UPDATE') THEN
            IF (UPPER(NEW.status) != UPPER(OLD.status)) THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_uuid, 'customer', 'Order Status Update', 'Your order status is now ' || NEW.status, NEW.id, 'order');
            END IF;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- If customer_id is not a valid UUID (e.g. guest/sms_auth), skip notification to prevent transaction rollback.
        NULL;
    END;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. 🚀 FINAL STABILITY VIEW REFRESH (WITH SECURITY INVOKER)
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
    COALESCE(r.current_lat, o.rider_lat, 0) AS rider_lat,
    COALESCE(r.current_lng, o.rider_lng, 0) AS rider_lng,
    r.bearing AS rider_bearing,
    r.speed AS rider_speed,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions,
    o.delivery_phone AS customer_phone,
    o.delivery_pincode,
    o.delivery_house_number,
    COALESCE(v.name, 'Restaurant') AS vendor_name,
    v.image_url AS vendor_image,
    COALESCE(r.name, 'Rider') AS rider_name,
    r.phone AS rider_phone,
    r.avatar_url AS rider_avatar,
    CASE 
        WHEN COALESCE(o.order_status, o.status) = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN COALESCE(o.order_status, o.status) = 'PLACED'          THEN 'Order Placed'
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED'        THEN 'Preparing'
        WHEN COALESCE(o.order_status, o.status) = 'COOKING'         THEN 'Cooking'
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP'       THEN 'Out for Delivery'
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED'       THEN 'Order Delivered'
        WHEN COALESCE(o.order_status, o.status) = 'CANCELLED'       THEN 'Cancelled'
        ELSE COALESCE(o.order_status, o.status, 'Unknown')
    END AS status_display,
    CASE 
        WHEN COALESCE(o.order_status, o.status) = 'PAYMENT_PENDING' THEN 0
        WHEN COALESCE(o.order_status, o.status) = 'PLACED'          THEN 1
        WHEN COALESCE(o.order_status, o.status) = 'ACCEPTED'        THEN 2
        WHEN COALESCE(o.order_status, o.status) = 'COOKING'         THEN 3
        WHEN COALESCE(o.order_status, o.status) = 'PICKED_UP'       THEN 4
        WHEN COALESCE(o.order_status, o.status) = 'DELIVERED'       THEN 5
        ELSE 1
    END AS current_step
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

-- 6. 🔓 FORCE PERMISSIONS
GRANT ALL ON public.orders TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
