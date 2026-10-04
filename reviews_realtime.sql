-- 🔔 ENABLE REALTIME FOR REVIEWS TABLE
-- This allows any client subscribing to reviews to receive them live.
alter publication supabase_realtime add table public.reviews;

-- 🔔 AUTOMATIC TRIGGER TO NOTIFY ADMIN ON NEW REVIEW
CREATE OR REPLACE FUNCTION notify_admin_on_review()
RETURNS TRIGGER AS $$
DECLARE
    v_order_short_id text;
    v_target_name text;
BEGIN
    v_order_short_id := SUBSTRING(NEW.order_id::text, 1, 8);
    
    IF NEW.target_type = 'vendor' THEN
        SELECT name INTO v_target_name FROM public.vendors WHERE id = NEW.vendor_id::uuid;
        INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
        VALUES (
            NEW.customer_id::uuid, 
            'admin', 
            'New Restaurant Review ⭐', 
            'Order #' || v_order_short_id || ': Customer rated ' || COALESCE(v_target_name, 'Restaurant') || ' ' || NEW.rating || ' stars. Comment: ' || COALESCE(NEW.comment, ''), 
            NEW.order_id::uuid, 
            'alert'
        );
    ELSE
        SELECT name INTO v_target_name FROM public.delivery_riders WHERE id = NEW.rider_id::uuid;
        INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
        VALUES (
            NEW.customer_id::uuid, 
            'admin', 
            'New Rider Review 🏍️', 
            'Order #' || v_order_short_id || ': Customer rated rider ' || COALESCE(v_target_name, 'Partner') || ' ' || NEW.rating || ' stars. Comment: ' || COALESCE(NEW.comment, ''), 
            NEW.order_id::uuid, 
            'alert'
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_admin_on_review ON public.reviews;
CREATE TRIGGER trg_notify_admin_on_review
    AFTER INSERT ON public.reviews
    FOR EACH ROW
    EXECUTE FUNCTION notify_admin_on_review();
