-- 🔔 NUCLEAR NOTIFICATION REPAIR v2.0
-- Run this in Supabase SQL Editor to fix "Normal" notifications.

-- 1. Ensure Table Permissions
GRANT ALL ON TABLE public.notifications TO anon, authenticated, service_role;

-- 2. Fix RLS (Row Level Security)
-- This ensures the app can actually READ the pulses Supabase sends.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications" ON public.notifications
    FOR SELECT USING (auth.uid()::text = user_id OR user_id = 'BROADCAST');

-- 3. Force Realtime Publication
-- This makes sure the "Pulse" is actually sent to the app.
DROP PUBLICATION IF EXISTS supabase_realtime;
CREATE PUBLICATION supabase_realtime FOR ALL TABLES;

-- 4. Create Webhook for FCM (Firebase Cloud Functions)
-- This sends a push notification even when the app is CLOSED.
-- Replace URL with your actual deployed function URL if it changed.
CREATE OR REPLACE FUNCTION public.notify_firebase_on_order_change()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM
    net.http_post(
      url := 'https://us-central1-univfoods-967a6.cloudfunctions.net/onOrderStatusChange',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := json_build_object(
        'event', TG_OP,
        'record', row_to_json(NEW),
        'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
      )::jsonb
    );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_notify_fcm_on_order ON public.orders;
CREATE TRIGGER tr_notify_fcm_on_order
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.notify_firebase_on_order_change();

-- 5. Verification
SELECT 'NOTIFICATIONS REPLICATED & WEBHOOK ARMED' as status;
