-- 🛵 REAL-TIME RIDER SYNC V13.2 (TYPE CASTING FIX)
-- 🎯 MISSION: Connect Rider App to Real-time and fix "Pending" details display.

BEGIN;

-- 1. ENABLE REAL-TIME FOR RIDERS AND ORDERS
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'delivery_riders') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_riders;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'orders') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'registrations') THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.registrations;
    END IF;
END $$;

-- 2. AUTO-APPROVE PENDING RIDERS FOR TEST (Bridge the gap)
-- Fixed: Explicitly casting IDs to handle both UUID and TEXT types.
INSERT INTO public.delivery_riders (id, name, phone, status, is_approved, is_online, created_at)
SELECT 
    id::uuid, 
    COALESCE(name, 'Rider'), 
    phone, 
    'ONLINE', 
    true, 
    true, 
    now()
FROM public.registrations
WHERE type = 'DELIVERY' AND status = 'PENDING'
ON CONFLICT (id) DO UPDATE SET
    is_approved = true,
    status = 'ONLINE',
    is_online = true;

-- Update the registration status to match
UPDATE public.registrations SET status = 'APPROVED' WHERE type = 'DELIVERY';

-- 3. FIX PROFILE DISPLAY VIEW
-- Fixed: JOIN with explicit casting to avoid "shell operator" error.
CREATE OR REPLACE VIEW public.rider_profile_view AS
SELECT 
    r.id,
    r.name,
    r.phone,
    r.status,
    r.is_approved,
    r.is_online,
    reg.email,
    reg.id::text as registration_id
FROM public.delivery_riders r
LEFT JOIN public.registrations reg ON (r.id::text = reg.id::text);

GRANT SELECT ON public.rider_profile_view TO anon, authenticated, service_role;

-- 4. REAL-TIME TRIGGER FOR NOTIFICATIONS
CREATE OR REPLACE FUNCTION notify_riders_of_new_order()
RETURNS TRIGGER AS $$
BEGIN
    IF (NEW.status = 'PLACED' OR NEW.status = 'ACCEPTED') THEN
        PERFORM pg_notify('rider_mission_pool', json_build_object('order_id', NEW.id, 'vendor_id', NEW.vendor_id)::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_notify_riders_order ON public.orders;
CREATE TRIGGER tr_notify_riders_order
AFTER INSERT OR UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE PROCEDURE notify_riders_of_new_order();

COMMIT;
NOTIFY pgrst, 'reload schema';
