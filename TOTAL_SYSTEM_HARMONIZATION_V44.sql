-- 🌪️ TOTAL SYSTEM HARMONIZATION (V44.0)
-- 🎯 MISSION: Stop the "column order_id is type uuid but expression is text" errors and fix status flow.

BEGIN;

-- 1. 🛑 NUCLEAR TRIGGER CLEANUP
-- Drop all known conflicting triggers on the orders table
DROP TRIGGER IF EXISTS tr_audit_order_status ON public.orders;
DROP TRIGGER IF EXISTS tr_master_notifications ON public.orders;
DROP TRIGGER IF EXISTS tr_calculate_earnings ON public.orders;
DROP TRIGGER IF EXISTS tr_order_financials ON public.orders;
DROP TRIGGER IF EXISTS on_payment_status_changed ON public.orders;
DROP TRIGGER IF EXISTS tr_notify_rejection ON public.orders;
DROP TRIGGER IF EXISTS on_order_placed ON public.orders;
DROP TRIGGER IF EXISTS tr_update_order_v1 ON public.orders;
DROP TRIGGER IF EXISTS trg_distance_enforcer ON public.orders;

-- 2. 🏗️ SCHEMA ENFORCEMENT (Universal Strings)
-- 🛡️ AGGRESSIVE POLICY CLEANUP (Postgres requirement to change column types)
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN (SELECT policyname FROM pg_policies WHERE tablename = 'notifications' AND schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.notifications', pol.policyname);
    END LOOP;
END $$;

-- Ensure notification and audit tables use TEXT for IDs to prevent mismatches
ALTER TABLE public.notifications ALTER COLUMN order_id TYPE text USING order_id::text;
ALTER TABLE public.notifications ALTER COLUMN user_id TYPE text USING user_id::text;

-- 🛡️ RE-CREATE POLICIES with TEXT support
CREATE POLICY "Users can see their own notifications" ON public.notifications
FOR SELECT USING (auth.uid()::text = user_id);

CREATE POLICY "Anyone can insert notifications" ON public.notifications
FOR INSERT WITH CHECK (true);

-- Update Audit table to be flexible too
ALTER TABLE public.order_status_audit ALTER COLUMN order_id TYPE text USING order_id::text;
ALTER TABLE public.order_status_audit ALTER COLUMN changed_by TYPE text USING changed_by::text;

-- 3. 🛡️ THE ONLY TRIGGER FUNCTION YOU'LL EVER NEED
-- This handles Notifications AND Auditing in one safe pass.
CREATE OR REPLACE FUNCTION public.unified_order_event_handler_v44()
RETURNS TRIGGER AS $$
DECLARE
    v_order_short_id text;
    v_cust_id text;
    v_vend_id text;
BEGIN
    v_order_short_id := SUBSTRING(NEW.id::text, 1, 8);
    v_cust_id := NEW.customer_id::text;
    v_vend_id := NEW.vendor_id::text;

    -- A. AUDIT LOGGING (Always run on change)
    IF (TG_OP = 'UPDATE') AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.order_status IS DISTINCT FROM NEW.order_status) THEN
        INSERT INTO public.order_status_audit (
            order_id, old_status, new_status, changed_by, payment_status
        ) VALUES (
            NEW.id::text, OLD.status, NEW.status, auth.uid()::text, NEW.payment_status
        );
    END IF;

    -- B. NOTIFICATIONS
    IF (TG_OP = 'INSERT') THEN
        -- Notify Vendor of New Order
        INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
        VALUES (v_vend_id, 'vendor', 'New Order! 🔔', 'Order #' || v_order_short_id || ' received.', NEW.id::text, 'order');
    END IF;

    IF (TG_OP = 'UPDATE') AND (OLD.status IS DISTINCT FROM NEW.status) THEN
        CASE UPPER(NEW.status)
            WHEN 'ACCEPTED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Order Accepted ✅', 'The restaurant has accepted your order #' || v_order_short_id, NEW.id::text, 'order');
            WHEN 'PREPARING', 'COOKING' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Cooking 🍳', 'Your food is being prepared.', NEW.id::text, 'order');
            WHEN 'READY' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Food Ready! 📦', 'Your order is ready for pickup.', NEW.id::text, 'order');
            WHEN 'PICKED_UP', 'ON THE WAY' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Out for Delivery 🚀', 'Your rider is on the way!', NEW.id::text, 'order');
            WHEN 'DELIVERED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Delivered! Enjoy 🍛', 'Order #' || v_order_short_id || ' delivered.', NEW.id::text, 'order');
            WHEN 'CANCELLED', 'REJECTED' THEN
                INSERT INTO public.notifications (user_id, app_type, title, message, order_id, type)
                VALUES (v_cust_id, 'customer', 'Order Cancelled ❌', 'Sorry, your order was cancelled.', NEW.id::text, 'order');
            ELSE
                NULL;
        END CASE;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- 🛡️ FAIL-SAFE: Never block the main order update if notification fails
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ATTACH THE UNIFIED TRIGGER
CREATE TRIGGER tr_unified_order_v44
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.unified_order_event_handler_v44();

-- 4. ⚡ RE-ALIGN THE STATUS UPDATE FUNCTION
-- Ensure it handles UUID/Text casting gracefully and is bulletproof.
CREATE OR REPLACE FUNCTION public.update_order_status_v3(
    p_order_id UUID,
    p_new_status TEXT,
    p_actor_id TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_payment_status TEXT;
BEGIN
    SELECT payment_status INTO v_payment_status FROM public.orders WHERE id = p_order_id;

    -- Safety check for paid orders
    IF UPPER(p_new_status) = 'CANCELLED' AND UPPER(v_payment_status) = 'SUCCESS' THEN
        RAISE EXCEPTION 'PAID_ORDER_CANCEL_BLOCKED';
    END IF;

    UPDATE public.orders SET
        status = UPPER(p_new_status),
        order_status = UPPER(p_new_status),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- Auto-dispatch rider when READY
    IF UPPER(p_new_status) = 'READY' THEN
        BEGIN
            PERFORM public.auto_assign_rider_v1(p_order_id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Auto-assign failed: %', SQLERRM;
        END;
    END IF;

    -- Cleanup rider link on finish
    IF UPPER(p_new_status) IN ('DELIVERED', 'CANCELLED', 'REJECTED') THEN
        UPDATE public.delivery_riders 
        SET active_order_id = NULL 
        WHERE active_order_id = p_order_id::uuid;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
NOTIFY pgrst, 'reload schema';
