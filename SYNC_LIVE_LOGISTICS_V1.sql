-- 🚀 LOGISTICS SYNC: Connect Rider Movement to Customer App (v104)
-- MISSION: Ensure the customer sees the rider moving in real-time on the map.

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
    o.item_total,
    o.delivery_fee,
    o.platform_fee,
    o.gst,
    o.tip_amount,
    COALESCE(o.delivery_address, 'Address not found') as delivery_address,
    o.delivery_lat,
    o.delivery_lng,
    o.vendor_lat,
    o.vendor_lng,
    -- 🔥 CRITICAL: Pull LIVE coordinates from the delivery_riders table
    COALESCE(r.current_lat, o.rider_lat, 0) as rider_lat,
    COALESCE(r.current_lng, o.rider_lng, 0) as rider_lng,
    r.heading as rider_heading,
    o.items,
    o.created_at,
    o.updated_at,
    o.cooking_instructions,
    o.delivery_phone as customer_phone,
    o.delivery_pincode,
    o.delivery_house_number,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Confirming Payment'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Order Accepted'
        WHEN o.order_status = 'COOKING' THEN 'Preparing your food'
        WHEN o.order_status = 'READY' THEN 'Food is Ready'
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
    v.name AS vendor_name,
    v.image_url AS vendor_image,
    v.logo_url AS vendor_logo,
    v.phone AS vendor_phone,
    v.address AS vendor_address,
    r.name AS rider_name,
    r.phone AS rider_phone,
    r.avatar_url AS rider_avatar,
    r.rating AS rider_rating,
    COALESCE(r.vehicle_number, r.vehicle_details) AS rider_vehicle
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

-- Grant permissions
GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
