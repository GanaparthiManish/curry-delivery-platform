-- 🚄 REALTIME VELOCITY ENGINE (V45.1)
-- 🎯 MISSION: Enable instant updates for Orders, Tracking, and Notifications.

BEGIN;

-- 1. 🚄 SET REPLICA IDENTITY TO FULL
-- This ensures that UPDATE/DELETE events contain ALL data, not just IDs.
-- This is what makes the UI update INSTANTLY without needing to refresh.
ALTER TABLE public.orders REPLICA IDENTITY FULL;
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
ALTER TABLE public.order_live_tracking REPLICA IDENTITY FULL;
ALTER TABLE public.delivery_riders REPLICA IDENTITY FULL;

COMMIT;

-- 🏁 VERIFY
SELECT 'Realtime Instant-Sync Activated!' as status;
