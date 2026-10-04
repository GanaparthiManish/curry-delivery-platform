-- 🛡️ ULTIMATE STABILITY & NOTIFICATION REPAIR (V52.0)
-- 🎯 MISSION: ENFORCE 5KM RADIUS ON MULTI-VENDOR ORDERS + CATEGORY FILTERING FIX
-- 🎯 REASON: Prevent 17km orders, fix Biryani category showing Juices, and restore Map visibility.

BEGIN;

-- 1. 🛡️ place_order_v4 (ENFORCE 5KM LIMIT + MASTER ID SYSTEM)
CREATE OR REPLACE FUNCTION public.place_order_v4(
    p_customer_id TEXT,
    p_vendor_items JSONB, 
    p_address TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_payment_method TEXT DEFAULT 'COD',
    p_instructions TEXT DEFAULT '',
    p_payment_status TEXT DEFAULT 'PENDING'
)
RETURNS TEXT AS $$
DECLARE
    v_master_id TEXT;
    v_sub_order JSONB;
    v_vendor_lat DOUBLE PRECISION;
    v_vendor_lng DOUBLE PRECISION;
    v_dist DOUBLE PRECISION;
    v_vendor_id UUID;
BEGIN
    v_master_id := gen_random_uuid()::TEXT;

    FOR v_sub_order IN SELECT * FROM jsonb_array_elements(p_vendor_items)
    LOOP
        v_vendor_id := (v_sub_order->>'vendor_id')::UUID;
        
        -- Get Vendor Location
        SELECT latitude, longitude INTO v_vendor_lat, v_vendor_lng 
        FROM public.vendors WHERE id = v_vendor_id;

        -- Calculate Distance
        v_dist := (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v_vendor_lat)) * cos(radians(v_vendor_lng) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v_vendor_lat))
                  ))));

        -- 🛑 BLOCK IF > 5KM (As requested: strict 5km radius)
        IF v_dist > 5.0 THEN
            RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Vendor % is % km away (Limit: 5km).', v_vendor_id, v_dist;
        END IF;

        INSERT INTO public.orders (
            id, master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions, created_at
        ) VALUES (
            gen_random_uuid()::TEXT,
            v_master_id,
            p_customer_id,
            v_vendor_id,
            v_sub_order->'items',
            (v_sub_order->>'total')::double precision,
            p_address,
            p_lat,
            p_lng,
            'PLACED',
            'PLACED',
            UPPER(p_payment_method),
            UPPER(p_payment_status),
            p_instructions,
            now()
        );
    END LOOP;

    RETURN v_master_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 🥘 get_popular_near_you_v2 (STRICT CATEGORY FILTERING)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT DEFAULT NULL
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(final_data)
        FROM (
            SELECT *
            FROM (
                SELECT 
                    p.*,
                    c.name as category_name,
                    (
                        SELECT row_to_json(tv)
                        FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                    ) as trusted_vendor
                FROM public.products p
                LEFT JOIN public.categories c ON p.category_id::text = c.id::text
                WHERE p.is_active = true
                  AND (
                    p_category_id IS NULL 
                    OR p_category_id = '' 
                    OR p_category_id = 'all'
                    OR p.category_id::text = p_category_id 
                    OR c.name = p_category_id
                    OR c.name ILIKE p_category_id
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL -- Enforces 5km via get_trusted_vendor_for_item_v2
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. 🗺️ get_nearby_vendors_v24 (RESTORE MAP VISIBILITY - 50KM)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT json_agg(v_data)
        FROM (
            SELECT 
                v.*,
                (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
                ))))::double precision as distance_km
            FROM public.vendors v
            WHERE (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= 50.0 -- 🌍 Increased to 50km for Map discovery
            ORDER BY (v.status = 'ONLINE') DESC, distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. 🔔 ULTIMATE NOTIFICATION TRIGGER
CREATE OR REPLACE FUNCTION public.proc_ultimate_notifications_v2()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id text := NEW.id::text;
    v_short_id text := SUBSTRING(NEW.id::text, 1, 8);
    v_cust_id text := NEW.customer_id::text;
    v_vend_id text := NEW.vendor_id::text;
    v_total text := COALESCE(NEW.total_amount::text, NEW.total::text, '0');
    v_rest_name text;
BEGIN
    SELECT name INTO v_rest_name FROM public.vendors WHERE id::text = v_vend_id;
    v_rest_name := COALESCE(v_rest_name, 'Royal Curry House');

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.notifications (user_id, title, message, body, type, event_type, order_id, role)
        VALUES (v_cust_id, '🔔 Order Confirmed', 'Your order #' || v_short_id || ' has been placed successfully.', 'Your order #' || v_short_id || ' has been placed successfully.', 'order', 'ORDER_PLACED', v_order_id, 'CUSTOMER');
        
        INSERT INTO public.notifications (user_id, title, message, body, type, event_type, order_id, role)
        VALUES (v_vend_id, '🚀 New Order Received', 'New order #' || v_short_id || ' (₹' || v_total || ') from customer.', 'New order #' || v_short_id || ' (₹' || v_total || ') from customer.', 'order', 'NEW_ORDER', v_order_id, 'VENDOR');
    END IF;

    IF (NEW.status IS DISTINCT FROM OLD.status AND (LOWER(NEW.status) = 'accepted' OR LOWER(NEW.status) = 'confirmed')) THEN
        INSERT INTO public.notifications (user_id, title, message, body, type, event_type, order_id, role)
        VALUES (v_cust_id, '🔔 Restaurant Accepted', v_rest_name || ' is preparing your food.', v_rest_name || ' is preparing your food.', 'order', 'ORDER_ACCEPTED', v_order_id, 'CUSTOMER');
    END IF;

    IF (NEW.status IS DISTINCT FROM OLD.status AND LOWER(NEW.status) = 'delivered') THEN
        INSERT INTO public.notifications (user_id, title, message, body, type, event_type, order_id, role)
        VALUES (v_cust_id, '🎉 Order Delivered', 'Enjoy your meal! 🍛', 'Enjoy your meal! 🍛', 'order', 'DELIVERED', v_order_id, 'CUSTOMER');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_ultimate_notifications_v2 ON public.orders;
CREATE TRIGGER tr_ultimate_notifications_v2
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.proc_ultimate_notifications_v2();

-- 5. Permissions
GRANT EXECUTE ON FUNCTION public.place_order_v4(TEXT, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
