-- 🚀 FIX: Full Bill Breakdown in Tracking View (v102.1)
-- MISSION: Ensure individual fees are available for real-time tracking.

BEGIN;

CREATE OR REPLACE VIEW public.order_tracking_stabilized_v1 AS
SELECT 
    o.id AS order_id,
    o.id AS id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    o.order_status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    o.item_total,        -- 💸 ADDED FOR BILLING
    o.delivery_fee,      -- 💸 ADDED FOR BILLING
    o.platform_fee,      -- 💸 ADDED FOR BILLING
    o.gst,               -- 💸 ADDED FOR BILLING
    o.tip_amount,        -- 💸 ADDED FOR BILLING
    COALESCE(o.delivery_address, 'Address not found') as delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.vendor_lat,
    o.vendor_lng,
    o.rider_lat,
    o.rider_lng,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions, -- ADDED
    o.delivery_phone as customer_phone, -- ADDED
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Payment Pending'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'PICKED_UP' THEN 'Out for Delivery'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status 
    END AS status_display,
    CASE 
        WHEN o.order_status = 'PLACED' THEN 1
        WHEN o.order_status = 'ACCEPTED' THEN 2
        WHEN o.order_status = 'COOKING' THEN 3
        WHEN o.order_status = 'PICKED_UP' THEN 4
        WHEN o.order_status = 'DELIVERED' THEN 5
        ELSE 1
    END AS current_step,
    v.name AS vendor_name,
    v.image_url AS vendor_image,
    v.logo_url AS vendor_logo,
    v.phone AS vendor_phone,
    v.address AS vendor_address,
    r.full_name AS rider_name,
    r.phone AS rider_phone,
    r.avatar_url AS rider_avatar,
    r.rating AS rider_rating,
    r.vehicle_details AS rider_vehicle
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

COMMIT;
NOTIFY pgrst, 'reload schema';
