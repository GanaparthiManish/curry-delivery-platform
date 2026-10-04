-- 🛠️ EMERGENCY NOTIFICATION RESTORE (ROLLBACK)
-- Run this IMMEDIATELY to fix Order Placement.

BEGIN;

-- 1. Remove the risky FCM webhook trigger that might be breaking the checkout
DROP TRIGGER IF EXISTS tr_notify_fcm_on_order ON public.orders;
DROP FUNCTION IF EXISTS public.notify_firebase_on_order_change();

-- 2. Restore the original working trigger from v60.0
-- (Ensuring it exists and hasn't been corrupted)
DROP TRIGGER IF EXISTS tr_ultimate_notifications ON public.orders;
CREATE TRIGGER tr_ultimate_notifications
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.proc_ultimate_notifications();

-- 3. Ensure the notifications table is accessible
GRANT ALL ON TABLE public.notifications TO anon, authenticated, service_role;

-- 4. Enable Realtime properly (Safe way)
DROP PUBLICATION IF EXISTS supabase_realtime;
CREATE PUBLICATION supabase_realtime FOR ALL TABLES;

COMMIT;

SELECT 'RESTORE COMPLETE! Orders should now place successfully.' as status;
