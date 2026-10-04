-- 🔔 RESTORE NOTIFICATIONS PERMISSIONS AND RLS
-- Unblocks the customer app from fetching, receiving real-time alerts, and marking notifications as read.
-- Run this script in your Supabase Dashboard SQL Editor.

BEGIN;

-- 1. Drop existing restrictive policies on notifications
DROP POLICY IF EXISTS "Users can see their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can view their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update their own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Public Notification Access" ON public.notifications;

-- 2. Enable RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 3. Create open RLS policy to allow customer app (running as anon/unauthenticated) to manage notifications
CREATE POLICY "Public Notification Access" ON public.notifications FOR ALL TO public USING (true) WITH CHECK (true);

COMMIT;

SELECT '✅ NOTIFICATION PERMISSIONS RESTORED SUCCESSFULLY!' as status;
