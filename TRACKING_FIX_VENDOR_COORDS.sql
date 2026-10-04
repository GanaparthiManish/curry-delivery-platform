-- 🚀 INDESTRUCTIBLE TRACKING FIX (V6 - High Visibility)
-- MISSION: Fix "My Address" bug and restore "hidden" orders in history.

-- 1. DROP OLD VIEW
DROP VIEW IF EXISTS public.order_tracking_stabilized_v1 CASCADE;

-- 2. REBUILD COD FUNCTION (V5.1 - Added Pincode/Phone)
DROP FUNCTION IF EXISTS public.place_order_stabilized_v5(text,text,jsonb,double precision,double precision,double precision,double precision,double precision,text,double precision,double precision,text,text,text,text,text) CASCADE;

CREATE OR REPLACE FUNCTION public.place_order_stabilized_v5(
    p_customer_id TEXT, p_vendor_id TEXT, p_items JSONB, p_total DOUBLE PRECISION,
    p_item_total DOUBLE PRECISION, p_delivery_fee DOUBLE PRECISION, p_platform_fee DOUBLE PRECISION,
    p_gst DOUBLE PRECISION, p_address TEXT, p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD', p_instructions TEXT DEFAULT '',
    p_address_id TEXT DEFAULT NULL, p_payment_status TEXT DEFAULT 'SUCCESS', p_payment_id TEXT DEFAULT 'COD_UNIV'
) RETURNS TEXT AS $$
    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst, vendor_lat, vendor_lng,
        delivery_address, delivery_lat, delivery_lng, order_status, status,
        payment_method, payment_status, payment_id, cooking_instructions, created_at,
        delivery_phone, delivery_house_number, delivery_pincode
    ) 
    SELECT 
        p_customer_id, p_vendor_id, p_items, p_total, p_item_total,
        p_delivery_fee, p_platform_fee, p_gst, COALESCE(latitude, 0), COALESCE(longitude, 0),
        p_address, p_lat, p_lng, 'PLACED', 'PLACED',
        p_payment_method, p_payment_status, p_payment_id, p_instructions, now(),
        (SELECT phone FROM public.customer_profiles WHERE id::text = p_customer_id::text LIMIT 1),
        split_part(p_address, ',', 1), -- Best guess for house number from provided address
        regexp_replace(p_address, '.*- ', '') -- Best guess for pincode
    FROM public.vendors WHERE id::text = p_vendor_id::text
    RETURNING id::text;
$$ LANGUAGE sql;

-- 3. REBUILD UPI FUNCTION (V22.1 - Perfect Alignment)
DROP FUNCTION IF EXISTS public.place_order_v22(jsonb) CASCADE;

CREATE OR REPLACE FUNCTION public.place_order_v22(p_params JSONB)
RETURNS TEXT AS $$
    INSERT INTO public.orders (
        customer_id, vendor_id, items, total_amount, item_total,
        delivery_fee, platform_fee, gst, vendor_lat, vendor_lng,
        delivery_address, delivery_lat, delivery_lng, order_status, status,
        payment_method, payment_status, cooking_instructions, created_at,
        delivery_phone, delivery_house_number, delivery_pincode
    ) 
    SELECT 
        p_params->>'customer_id', (p_params->>'vendor_id')::UUID, p_params->'items',
        (p_params->>'total')::double precision, (p_params->>'item_total')::double precision,
        COALESCE((p_params->>'delivery_fee')::double precision, 0),
        COALESCE((p_params->>'platform_fee')::double precision, 0),
        COALESCE((p_params->>'gst')::double precision, 0),
        COALESCE(latitude, 0), COALESCE(longitude, 0),
        p_params->>'address', (p_params->>'lat')::double precision, (p_params->>'lng')::double precision,
        'PAYMENT_PENDING', 'PAYMENT_PENDING', 
        COALESCE(p_params->>'payment_method', 'UPI'), 'PENDING', 
        p_params->>'cooking_instructions', now(),
        p_params->>'customer_phone', p_params->>'house_number', p_params->>'pincode'
    FROM public.vendors WHERE id::text = (p_params->>'vendor_id')::text
    RETURNING id::text;
$$ LANGUAGE sql;

-- 4. ULTRA-RICH TRACKING VIEW
CREATE OR REPLACE VIEW public.order_tracking_stabilized_v1 AS
SELECT
    o.id AS order_id,
    o.id AS id,
    o.customer_id,
    o.vendor_id,
    o.rider_id,
    COALESCE(o.order_status, o.status, 'PLACED') as order_status,
    o.payment_status,
    o.payment_method,
    o.total_amount,
    o.item_total,
    o.delivery_fee,
    o.platform_fee,
    o.gst,
    COALESCE(o.delivery_address, 'My Address') as delivery_address,
    COALESCE(o.delivery_address, 'My Address') as address, -- Duplicate for compatibility
    o.delivery_house_number,
    o.delivery_pincode,
    o.delivery_phone,
    COALESCE(o.customer_phone, o.delivery_phone) as customer_phone,
    o.cooking_instructions as delivery_instructions,
    COALESCE(NULLIF(o.vendor_lat, 0), v.latitude, 0) as vendor_lat,
    COALESCE(NULLIF(o.vendor_lng, 0), v.longitude, 0) as vendor_lng,
    COALESCE(o.delivery_lat, 0) as delivery_lat,
    COALESCE(o.delivery_lng, 0) as delivery_lng,
    COALESCE(r.current_lat, 0) as rider_lat,
    COALESCE(r.current_lng, 0) as rider_lng,
    v.name as vendor_name,
    v.image_url as vendor_image,
    v.phone as vendor_phone,
    v.address as vendor_address,
    r.name as rider_name,
    r.phone as rider_phone,
    CASE 
        WHEN o.order_status = 'PAYMENT_PENDING' THEN 'Payment Processing'
        WHEN o.order_status = 'PLACED' THEN 'Order Placed'
        WHEN o.order_status = 'ACCEPTED' THEN 'Preparing'
        WHEN o.order_status = 'COOKING' THEN 'Cooking'
        WHEN o.order_status = 'PICKED_UP' THEN 'Out for Delivery'
        WHEN o.order_status = 'DELIVERED' THEN 'Delivered'
        WHEN o.order_status = 'CANCELLED' THEN 'Cancelled'
        ELSE o.order_status 
    END as status_display,
    o.created_at,
    o.items
FROM public.orders o
LEFT JOIN public.vendors v ON (o.vendor_id::text) = (v.id::text)
LEFT JOIN public.delivery_riders r ON (o.rider_id::text) = (r.id::text);

GRANT SELECT ON public.order_tracking_stabilized_v1 TO anon, authenticated, service_role;
NOTIFY pgrst, 'reload schema';
