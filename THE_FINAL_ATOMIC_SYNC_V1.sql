-- 🚀 THE FINAL ATOMIC SYNC: Zero-Pending & Full History (v107)
-- MISSION: Absolute elimination of "Payment Pending" and restoration of all history.

BEGIN;

-- 1. Hard-Sync the RIDERS table schema
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS current_lat double precision DEFAULT 0;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS current_lng double precision DEFAULT 0;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS heading double precision DEFAULT 0;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS vehicle_number text;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS vehicle_details text;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS name text;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS rating double precision DEFAULT 4.5;
ALTER TABLE public.delivery_riders ADD COLUMN IF NOT EXISTS avatar_url text;

-- 2. NUCLEAR RPC: confirm_upi_payment_v2
-- This is what kills the "Payment Pending" stickiness.
CREATE OR REPLACE FUNCTION public.confirm_upi_payment_v2(p_order_id uuid, p_payment_id text)
RETURNS void AS $$
BEGIN
    UPDATE public.orders
    SET 
        order_status = 'PLACED',
        status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = now()
    WHERE id = p_order_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. UPDATED RPC: place_order_stabilized_v5 (For COD)
CREATE OR REPLACE FUNCTION public.place_order_stabilized_v5(
    p_customer_id TEXT, p_vendor_id TEXT, p_items JSONB, p_total DOUBLE PRECISION,
    p_item_total DOUBLE PRECISION, p_delivery_fee DOUBLE PRECISION,
    p_platform_fee DOUBLE PRECISION, p_gst DOUBLE PRECISION, p_address TEXT,
    p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION, p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '', p_address_id TEXT DEFAULT NULL,
    p_payment_status TEXT DEFAULT 'PENDING', p_payment_id TEXT DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE v_order_id TEXT; v_initial_status TEXT; v_final_payment_status TEXT;
BEGIN
    IF p_payment_method = 'COD' THEN
        v_initial_status := 'PLACED'; v_final_payment_status := 'SUCCESS';
    ELSE
        v_initial_status := 'PAYMENT_PENDING'; v_final_payment_status := 'PENDING';
    END IF;
    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst, delivery_address, delivery_lat, delivery_lng, 
        order_status, status, payment_method, payment_status, payment_id,
        cooking_instructions, created_at
    ) VALUES (
        p_customer_id, p_vendor_id, p_items, p_total, p_item_total,
        p_delivery_fee, p_platform_fee, p_gst, p_address, p_lat, p_lng,
        v_initial_status, v_initial_status, p_payment_method, v_final_payment_status, p_payment_id,
        p_instructions, now()
    ) RETURNING id::text INTO v_order_id;
    RETURN v_order_id;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Safely Rebuild the Stabilized View (Restoring ALL history)
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;
CREATE VIEW public.order_tracking_stabilized_v1 AS
SELECT 
    o.id AS order_id, o.id AS id, o.customer_id, o.vendor_id, o.rider_id,
    o.order_status, o.payment_status, o.payment_method, o.total_amount,
    o.item_total, o.delivery_fee, o.platform_fee, o.gst, o.tip_amount,
    COALESCE(o.delivery_address, 'Address not found') as delivery_address,
    o.delivery_lat, o.delivery_lng, o.vendor_lat, o.vendor_lng,
    COALESCE(r.current_lat, o.rider_lat, 0) as rider_lat,
    COALESCE(r.current_lng, o.rider_lng, 0) as rider_lng,
    COALESCE(r.heading, 0) as rider_heading,
    o.items, o.created_at, o.updated_at, o.cooking_instructions,
    o.delivery_phone as customer_phone, o.delivery_pincode, o.delivery_house_number,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'PICKED_UP' THEN 'Rider is on the way'
        WHEN o.order_status = 'DELIVERED' THEN 'Order Delivered'
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
    v.name AS vendor_name, v.image_url AS vendor_image,
    r.name AS rider_name, r.phone AS rider_phone,
    r.avatar_url AS rider_avatar, r.rating AS rider_rating,
    COALESCE(r.vehicle_number, r.vehicle_details, 'Bike') AS rider_vehicle
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- 5. Finalize
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;
COMMIT;
NOTIFY pgrst, 'reload schema';
