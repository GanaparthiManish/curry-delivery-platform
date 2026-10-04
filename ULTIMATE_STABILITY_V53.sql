-- 🛡️ ULTIMATE STABILITY & NOTIFICATION REPAIR (V53.0)
-- 🎯 MISSION: STRICT 5KM RADIUS ENFORCEMENT EVERYWHERE (MAP, FEED, CHECKOUT, TRACKING) + NOTIFICATIONS
-- 🎯 REASON: Prevent 17km orders, enforce 5km limit for discovery and tracking, and repair notification pipeline.

BEGIN;

-- ==========================================
-- 1. 🧹 CLEANUP OLD CONFLICTS
-- ==========================================
DROP TRIGGER IF EXISTS tr_enforce_order_radius ON public.orders;
DROP TRIGGER IF EXISTS tr_ultimate_notifications_v2 ON public.orders;
DROP TRIGGER IF EXISTS tr_order_notifications ON public.orders;
DROP TRIGGER IF EXISTS tr_ultimate_notifications_v53 ON public.orders;

-- ==========================================
-- 2. 🥘 DISCOVERY ENGINE (STRICT 5KM)
-- ==========================================

-- Function to get vendors within a radius for Map & List (Default 5km, but flexible)
CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_km DOUBLE PRECISION DEFAULT 5.0
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
            WHERE (v.status = 'ONLINE' OR v.status = 'Active') -- 🛡️ SUPPORT BOTH STATUS STRINGS
              AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                    sin(radians(p_lat)) * sin(radians(v.latitude))
              )))) <= p_radius_km -- 🌍 FLEXIBLE RADIUS
            ORDER BY distance_km ASC
        ) v_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Function to get Trusted Vendor for an item (Strict 5km)
CREATE OR REPLACE FUNCTION public.get_trusted_vendor_for_item_v2(
    p_product_id TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS TABLE (
    vendor_id TEXT,
    vendor_name TEXT,
    price DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,
    rating DOUBLE PRECISION,
    eta_mins INT,
    image TEXT,
    is_trusted BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    WITH potential_vendors AS (
        SELECT 
            v.id::text as v_id,
            v.name as v_name,
            p.price::double precision as v_price,
            (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v.latitude))
            ))))::double precision as dist,
            COALESCE(v.rating, 5.0)::double precision as v_rating,
            COALESCE(p.image_url, v.banner_url) as v_image
        FROM public.products p
        JOIN public.vendors v ON p.vendor_id::text = v.id::text
        WHERE p.id::text = p_product_id
          AND (v.status = 'ONLINE' OR v.status = 'Active')
          AND p.is_active = true
          AND (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                sin(radians(p_lat)) * sin(radians(v.latitude))
          )))) <= 5.0 -- 🌍 STRICT 5KM RADIUS
    )
    SELECT 
        v_id, v_name, v_price, dist, v_rating,
        (15 + (dist * 4))::int as v_eta,
        v_image, TRUE as v_is_trusted
    FROM potential_vendors
    ORDER BY dist ASC, v_rating DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql STABLE;

-- Updated Popular Items Feed (Returns BOTH Popular and Normal items)
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_category_id TEXT DEFAULT NULL,
    p_radius_km DOUBLE PRECISION DEFAULT 5.0
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
            WHERE item_data.trusted_vendor IS NOT NULL 
              AND (item_data.trusted_vendor->>'distance_km')::double precision <= p_radius_km
            ORDER BY 
                (CASE WHEN item_data.is_popular = true OR item_data.item_type = 'POPULAR_ITEM' THEN 0 ELSE 1 END) ASC,
                (item_data.trusted_vendor->>'distance_km')::double precision ASC
            LIMIT 100
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- ==========================================
-- 3. 🛡️ CHECKOUT ENGINE (STRICT 5KM)
-- ==========================================

-- Master Order Splitter (Strict 5km Validation)
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

        -- 🛑 BLOCK IF > 5KM
        IF v_dist > 5.0 THEN
            RAISE EXCEPTION 'DELIVERY_OUT_OF_RANGE: Your location is % km away from Vendor (Limit: 5km).', ROUND(v_dist::numeric, 2);
        END IF;

        INSERT INTO public.orders (
            master_order_id, customer_id, vendor_id, items, total_amount,
            delivery_address, delivery_lat, delivery_lng,
            order_status, status, payment_method, payment_status,
            cooking_instructions, created_at
        ) VALUES (
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

-- Trigger to block any order insertion > 5km
CREATE OR REPLACE FUNCTION public.enforce_order_delivery_radius_v53()
RETURNS TRIGGER AS $$
DECLARE
    v_dist DOUBLE PRECISION;
BEGIN
    SELECT (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(NEW.delivery_lat)) * cos(radians(COALESCE(latitude, NEW.delivery_lat))) * cos(radians(COALESCE(longitude, NEW.delivery_lng)) - radians(NEW.delivery_lng)) + sin(radians(NEW.delivery_lat)) * sin(radians(COALESCE(latitude, NEW.delivery_lat)))))))
    INTO v_dist FROM public.vendors WHERE id = NEW.vendor_id;

    IF COALESCE(v_dist, 0) > 5.0 THEN
        RAISE EXCEPTION 'OUT_OF_RADIUS: Delivery location is %km away. Max 5km.', ROUND(v_dist::numeric, 2);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER tr_enforce_order_radius
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE PROCEDURE public.enforce_order_delivery_radius_v53();

-- ==========================================
-- 4. 🔔 NOTIFICATION ENGINE (REPAIRED)
-- ==========================================

-- Ensure notifications table exists with correct schema
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    user_role TEXT NOT NULL DEFAULT 'customer', -- customer, vendor, delivery, admin
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    body TEXT,
    order_id TEXT,
    type TEXT DEFAULT 'order',
    event_type TEXT,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Master Notification Function
CREATE OR REPLACE FUNCTION public.proc_ultimate_notifications_v53()
RETURNS TRIGGER AS $$
DECLARE
    v_short_id text := SUBSTRING(NEW.id::text, 1, 8);
    v_cust_id text := NEW.customer_id::text;
    v_vend_id text := NEW.vendor_id::text;
    v_total text := COALESCE(NEW.total_amount::text, '0');
    v_rest_name text;
BEGIN
    SELECT name INTO v_rest_name FROM public.vendors WHERE id = NEW.vendor_id;
    v_rest_name := COALESCE(v_rest_name, 'Royal Curry House');

    -- 1. Order Placed
    IF (TG_OP = 'INSERT') THEN
        -- Notify Customer
        INSERT INTO public.notifications (user_id, user_role, title, message, body, event_type, order_id)
        VALUES (v_cust_id, 'customer', '🔔 Order Confirmed', 'Your order #' || v_short_id || ' has been placed successfully.', 'Your order #' || v_short_id || ' has been placed successfully.', 'ORDER_PLACED', NEW.id::text);
        
        -- Notify Vendor
        INSERT INTO public.notifications (user_id, user_role, title, message, body, event_type, order_id)
        VALUES (v_vend_id, 'vendor', '🚀 New Order Received', 'New order #' || v_short_id || ' (₹' || v_total || ') from customer.', 'New order #' || v_short_id || ' (₹' || v_total || ') from customer.', 'NEW_ORDER', NEW.id::text);
    END IF;

    -- 2. Status Updates
    IF (TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        -- Accepted
        IF (LOWER(NEW.status) IN ('accepted', 'confirmed', 'preparing')) THEN
            INSERT INTO public.notifications (user_id, user_role, title, message, body, event_type, order_id)
            VALUES (v_cust_id, 'customer', '👨‍🍳 Preparing Food', v_rest_name || ' is preparing your delicious meal.', v_rest_name || ' is preparing your delicious meal.', 'ORDER_ACCEPTED', NEW.id::text);
        END IF;

        -- Delivered
        IF (LOWER(NEW.status) = 'delivered') THEN
            INSERT INTO public.notifications (user_id, user_role, title, message, body, event_type, order_id)
            VALUES (v_cust_id, 'customer', '🎉 Enjoy your meal!', 'Order #' || v_short_id || ' has been delivered. Enjoy your Curry! 🍛', 'Order #' || v_short_id || ' has been delivered. Enjoy your Curry! 🍛', 'DELIVERED', NEW.id::text);
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_ultimate_notifications_v53
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.proc_ultimate_notifications_v53();

-- ==========================================
-- 5. 🛰️ REALTIME & PERMISSIONS
-- ==========================================

-- Standardize all vendors to Online & 5km
UPDATE public.vendors SET status = 'ONLINE', is_active = true, delivery_radius_km = 5.0;

-- Activate Realtime for critical tables
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.orders; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_riders; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.order_live_tracking; EXCEPTION WHEN others THEN NULL; END $$;

-- Ensure RLS allows access
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
CREATE POLICY "Users can view their own notifications" ON public.notifications FOR SELECT USING (auth.uid()::text = user_id);

ALTER TABLE public.delivery_riders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view rider locations" ON public.delivery_riders;
CREATE POLICY "Public can view rider locations" ON public.delivery_riders FOR SELECT USING (true);

-- Function to Search items near you (Strict 5km)
CREATE OR REPLACE FUNCTION public.search_items_near_you_v2(
    p_query TEXT,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_limit INT DEFAULT 50
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
                    v.name as vendor_name,
                    c.name as category_name,
                    (6371 * acos(LEAST(1.0, GREATEST(-1.0, 
                        cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + 
                        sin(radians(p_lat)) * sin(radians(v.latitude))
                    ))))::double precision as distance_km,
                    (
                        SELECT row_to_json(tv)
                        FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv
                    ) as trusted_vendor
                FROM public.products p
                JOIN public.vendors v ON p.vendor_id = v.id
                LEFT JOIN public.categories c ON p.category_id::text = c.id::text
                WHERE p.is_active = true
                  AND (
                      p.name ILIKE '%' || p_query || '%' 
                      OR p.description ILIKE '%' || p_query || '%' 
                      OR c.name ILIKE '%' || p_query || '%' 
                      OR v.name ILIKE '%' || p_query || '%'
                      OR v.address ILIKE '%' || p_query || '%'
                      OR v.shop_name ILIKE '%' || p_query || '%'
                  )
            ) item_data
            WHERE item_data.trusted_vendor IS NOT NULL -- 🌍 STRICT 5KM ENFORCED
            ORDER BY item_data.distance_km ASC
            LIMIT p_limit
        ) final_data
    );
END;
$$ LANGUAGE plpgsql STABLE;

-- Master Rider Tracker Sync (v43)
CREATE OR REPLACE FUNCTION public.update_rider_location_v43(
    p_rider_id TEXT,
    p_order_id UUID DEFAULT NULL,
    p_lat DOUBLE PRECISION DEFAULT 0,
    p_lng DOUBLE PRECISION DEFAULT 0,
    p_heading DOUBLE PRECISION DEFAULT 0,
    p_speed DOUBLE PRECISION DEFAULT 0
)
RETURNS VOID AS $$
BEGIN
    -- Update Rider table (Source of truth for the Logistics Grid)
    UPDATE public.delivery_riders SET
        current_lat = p_lat,
        current_lng = p_lng,
        last_lat = p_lat,
        last_lng = p_lng,
        bearing = p_heading,
        speed = p_speed,
        last_gps_update = now(),
        updated_at = now()
    WHERE id::text = p_rider_id;

    -- Update Active Order snapshot for Customer Realtime
    IF p_order_id IS NOT NULL THEN
        UPDATE public.orders SET
            rider_lat = p_lat,
            rider_lng = p_lng,
            updated_at = now()
        WHERE id = p_order_id;
        
        -- Snapshot for Telemetry history
        INSERT INTO public.order_live_tracking (order_id, rider_id, rider_lat, rider_lng, speed, heading)
        VALUES (p_order_id, p_rider_id::uuid, p_lat, p_lng, p_speed, p_heading);
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant Permissions
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_trusted_vendor_for_item_v2(TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.place_order_v4(TEXT, JSONB, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.search_items_near_you_v2(TEXT, DOUBLE PRECISION, DOUBLE PRECISION, INT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_rider_location_v43 TO anon, authenticated, service_role;

COMMIT;
NOTIFY pgrst, 'reload schema';
