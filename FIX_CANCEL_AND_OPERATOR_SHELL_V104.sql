-- 🚨 FINAL CANCELLATION & OPERATOR SHELL FIX (V104)
-- 🎯 MISSION: Fix "operator is only a shell: text = uuid" and unblock order cancellation.
-- 🚀 TARGET: Fix the mismatch between TEXT and UUID types that blocks updates.

BEGIN;

-- 1. 🛡️ DROP ALL CONFLICTING VERSIONS OF update_order_status_v3
-- This ensures we don't have multiple functions with the same name but different parameter types.
DROP FUNCTION IF EXISTS public.update_order_status_v3(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT);
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.update_order_status_v3(TEXT, TEXT, TEXT);

-- 2. 🛡️ RECREATE THE MASTER STATUS UPDATE RPC (ROBUST VERSION)
-- We accept TEXT for p_order_id to maximize compatibility with the Flutter app.
CREATE OR REPLACE FUNCTION public.update_order_status_v3(
    p_order_id TEXT,
    p_new_status TEXT,
    p_actor_id TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    -- We cast everything to TEXT for the comparison to avoid "shell operator" errors.
    UPDATE public.orders 
    SET 
        status = UPPER(p_new_status),
        order_status = UPPER(p_new_status),
        updated_at = NOW()
    WHERE id::text = p_order_id::text;
    
    -- Also update the rider if the order is finished
    IF UPPER(p_new_status) IN ('DELIVERED', 'CANCELLED', 'REJECTED') THEN
        UPDATE public.delivery_riders 
        SET active_order_id = NULL 
        WHERE active_order_id::text = p_order_id::text;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. 🛡️ RE-RE-FIX NOTIFICATION TRIGGER (Removes deadly ::uuid cast)
CREATE OR REPLACE FUNCTION public.handle_core_notifications_v3()
RETURNS TRIGGER AS $$
DECLARE
    v_customer_id TEXT;
    v_order_short_id TEXT;
BEGIN
    v_order_short_id := SUBSTRING(NEW.id::TEXT, 1, 8);
    -- 🚨 FIX: We treat customer_id as TEXT throughout to support SMS/Guest users.
    v_customer_id := NEW.customer_id::TEXT;

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
        VALUES (v_customer_id, 'customer', '🎉 Order Placed!',
            'Your order #' || v_order_short_id || ' was placed.', NEW.id, 'order');
    END IF;

    IF (TG_OP = 'UPDATE' AND UPPER(NEW.status) != UPPER(COALESCE(OLD.status, ''))) THEN
        CASE UPPER(NEW.status)
            WHEN 'ACCEPTED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '👨‍🍳 Order Accepted!',
                    'Restaurant is preparing order #' || v_order_short_id, NEW.id, 'order');
            WHEN 'PREPARING' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '🍳 Preparing Your Food',
                    'Your delicious meal is being cooked!', NEW.id, 'order');
            WHEN 'READY' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '✅ Food Ready!',
                    'Your order is ready, rider is picking it up.', NEW.id, 'order');
            WHEN 'PICKED_UP' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '🚴 Out for Delivery!',
                    'Your order is on the way!', NEW.id, 'order');
            WHEN 'DELIVERED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '🎉 Delivered!',
                    'Enjoy your meal! Rate your experience ⭐', NEW.id, 'order');
            WHEN 'CANCELLED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_customer_id, 'customer', '❌ Order Cancelled',
                    'Your order #' || v_order_short_id || ' was cancelled.', NEW.id, 'order');
            ELSE NULL;
        END CASE;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Notification trigger failed: %', SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. 🛡️ ENSURE NOTIFICATIONS TABLE SUPPORTS TEXT IDs
DO $$
BEGIN
    -- If user_id is UUID, it will fail for guest users. We must make it TEXT.
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'notifications' AND column_name = 'user_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.notifications ALTER COLUMN user_id TYPE TEXT;
    END IF;
END $$;

-- 5. 🛡️ GRANT PERMISSIONS
GRANT EXECUTE ON FUNCTION public.update_order_status_v3 TO anon, authenticated, service_role;

COMMIT;

-- 🔄 RELOAD SCHEMA
NOTIFY pgrst, 'reload schema';
SELECT '✅ CANCELLATION SYSTEM REPAIRED!' as status;
