-- 🛡️ UPI STABILITY & AUDIT ENGINE
-- MISSION: Prevent unauthorized cancellations and track the origin of all status changes.

BEGIN;

-- 1. CREATE AUDIT LOG TABLE
CREATE TABLE IF NOT EXISTS public.order_status_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL,
    old_status TEXT,
    new_status TEXT,
    changed_by TEXT, -- Stores auth.uid() or 'SYSTEM'
    payment_status TEXT,
    changed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. CREATE AUDIT FUNCTION
CREATE OR REPLACE FUNCTION public.log_order_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.status IS DISTINCT FROM NEW.status) OR (OLD.order_status IS DISTINCT FROM NEW.order_status) THEN
        INSERT INTO public.order_status_audit (
            order_id, 
            old_status, 
            new_status, 
            changed_by, 
            payment_status
        ) VALUES (
            NEW.id, 
            OLD.status, 
            NEW.status, 
            auth.uid()::text, 
            NEW.payment_status
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. ATTACH AUDIT TRIGGER
DROP TRIGGER IF EXISTS tr_audit_order_status ON public.orders;
CREATE TRIGGER tr_audit_order_status
BEFORE UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.log_order_status_change();

-- 4. HARDEN STATUS TRANSITION RPC
-- MISSION: Block 'CANCELLED' status if payment is already successful.
DROP FUNCTION IF EXISTS public.update_order_status_v3(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.update_order_status_v3(
    p_order_id UUID,
    p_new_status TEXT,
    p_actor_id TEXT DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_current_status TEXT;
    v_payment_status TEXT;
BEGIN
    SELECT status, payment_status INTO v_current_status, v_payment_status 
    FROM public.orders WHERE id = p_order_id;

    -- 🛡️ DEFENSIVE GUARD: Don't allow cancellation of paid orders via this RPC
    IF UPPER(p_new_status) = 'CANCELLED' AND UPPER(v_payment_status) = 'SUCCESS' THEN
        RAISE EXCEPTION 'ILLEGAL_TRANSITION: Cannot cancel an order that has already been paid via UPI.';
    END IF;

    -- Only update if status is actually changing
    IF v_current_status = p_new_status THEN
        RETURN;
    END IF;

    UPDATE public.orders 
    SET status = UPPER(p_new_status),
        order_status = UPPER(p_new_status), -- Keep in sync
        updated_at = NOW(),
        is_settled = CASE WHEN UPPER(p_new_status) = 'DELIVERED' THEN true ELSE is_settled END
    WHERE id = p_order_id;

    -- Trigger Delivery Search when READY
    IF UPPER(p_new_status) = 'READY' THEN
        PERFORM public.auto_assign_rider_v1(p_order_id);
    END IF;

    -- Release Rider on completion
    IF UPPER(p_new_status) IN ('DELIVERED', 'CANCELLED', 'REJECTED') THEN
        UPDATE public.delivery_riders 
        SET active_order_id = NULL 
        WHERE active_order_id = p_order_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. UPGRADE UPI CONFIRMATION (RESCUE MISSION)
-- MISSION: If a payment is confirmed, FORCE the order to PLACED even if it was previously failed/cancelled.
DROP FUNCTION IF EXISTS public.confirm_upi_payment_v2(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.confirm_upi_payment_v2(p_order_id UUID, p_payment_id TEXT)
RETURNS TEXT AS $$
DECLARE
    v_current_status TEXT;
BEGIN
    -- 1. Check current status for logging/rescue
    SELECT status INTO v_current_status FROM public.orders WHERE id = p_order_id;

    -- 2. Force Update to PLACED (Overwrites any 'payment_failed' or accidental 'cancelled')
    UPDATE public.orders
    SET 
        status = 'PLACED',
        order_status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_state = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = NOW()
    WHERE id = p_order_id;

    IF NOT FOUND THEN
        RETURN 'ERROR: Order not found';
    END IF;

    RETURN 'SUCCESS: Order rescued and marked as PLACED';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
