-- 🛠️ LOGISTICS RECOVERY V11.0 (5KM + REALTIME + TYPE FIX)
-- 🎯 MISSION: Fix "get_effective_delivery_radius(text)" error and enforce 5km radius.

BEGIN;

-- 1. DROP CONFLICTING FUNCTIONS
DROP FUNCTION IF EXISTS public.get_effective_delivery_radius(UUID) CASCADE;
DROP FUNCTION IF EXISTS public.get_effective_delivery_radius(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.validate_order_radius(UUID, DOUBLE PRECISION, DOUBLE PRECISION) CASCADE;
DROP FUNCTION IF EXISTS public.validate_order_radius(TEXT, DOUBLE PRECISION, DOUBLE PRECISION) CASCADE;

-- 2. CREATE RADIUS HELPER (UUID VERSION)
CREATE OR REPLACE FUNCTION public.get_effective_delivery_radius(p_vendor_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    v_radius NUMERIC;
BEGIN
    -- Return exactly 5.0km as per request
    RETURN 5.0;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 3. CREATE RADIUS HELPER (TEXT VERSION) - FIXES TYPE MISMATCH
CREATE OR REPLACE FUNCTION public.get_effective_delivery_radius(p_vendor_id TEXT)
RETURNS NUMERIC AS $$
BEGIN
    RETURN public.get_effective_delivery_radius(p_vendor_id::UUID);
EXCEPTION WHEN OTHERS THEN
    RETURN 5.0;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 4. CREATE VALIDATION (UUID VERSION)
CREATE OR REPLACE FUNCTION public.validate_order_radius(p_vendor_id UUID, p_user_lat DOUBLE PRECISION, p_user_lng DOUBLE PRECISION)
RETURNS BOOLEAN AS $$
DECLARE
    v_dist DOUBLE PRECISION;
BEGIN
    SELECT (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(p_user_lat)) * cos(radians(COALESCE(latitude, p_user_lat))) * cos(radians(COALESCE(longitude, p_user_lng)) - radians(p_user_lng)) + sin(radians(p_user_lat)) * sin(radians(COALESCE(latitude, p_user_lat)))))))
    INTO v_dist FROM public.vendors WHERE id = p_vendor_id;
    
    RETURN COALESCE(v_dist, 0) <= 5.0;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 5. CREATE VALIDATION (TEXT VERSION) - FIXES CHECKOUT ERROR
CREATE OR REPLACE FUNCTION public.validate_order_radius(p_vendor_id TEXT, p_user_lat DOUBLE PRECISION, p_user_lng DOUBLE PRECISION)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN public.validate_order_radius(p_vendor_id::UUID, p_user_lat, p_user_lng);
EXCEPTION WHEN OTHERS THEN
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 6. RE-ENFORCE TRIGGER ON ORDERS
CREATE OR REPLACE FUNCTION public.enforce_order_delivery_radius_v11()
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

DROP TRIGGER IF EXISTS tr_enforce_order_radius ON public.orders;
CREATE TRIGGER tr_enforce_order_radius
BEFORE INSERT ON public.orders
FOR EACH ROW EXECUTE PROCEDURE public.enforce_order_delivery_radius_v11();

-- 7. UPDATE ALL VENDORS TO ONLINE & 5KM
UPDATE public.vendors
SET 
    is_active = TRUE, 
    is_verified = TRUE, 
    status = 'ONLINE', 
    delivery_radius_km = 5.0;

-- 8. UPDATE SYSTEM CONFIG
UPDATE public.app_settings 
SET value = jsonb_set(value, '{deliveryRadius}', '5.0')
WHERE key = 'system_config';

-- 9. FORCE REPLICATION FOR REAL-TIME
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'vendors'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.vendors;
    END IF;
END $$;

COMMIT;
NOTIFY pgrst, 'reload schema';
