-- 🚀 FIX: Auto-Place order if payment is confirmed as captured but stuck in pending
-- This handles situations where Razorpay webhook is missing or fails.

CREATE OR REPLACE FUNCTION public.fix_stuck_upi_order(p_order_id UUID, p_razorpay_payment_id TEXT)
RETURNS TEXT AS $$
DECLARE
    v_status TEXT;
BEGIN
    -- 1. Get current status
    SELECT order_status INTO v_status FROM public.orders WHERE id = p_order_id;
    
    IF v_status != 'PAYMENT_PENDING' AND v_status != 'pending' THEN
        RETURN 'Order is not in pending state: ' || v_status;
    END IF;

    -- 2. Update order to PLACED and set payment details
    UPDATE public.orders 
    SET 
        order_status = 'PLACED',
        payment_status = 'SUCCESS',
        payment_id = p_razorpay_payment_id,
        updated_at = now()
    WHERE id = p_order_id;

    -- 3. Notify Support Table as well
    UPDATE public.support_chats
    SET status = 'RESOLVED'
    WHERE order_id = p_order_id AND status = 'BOT';

    RETURN 'SUCCESS: Order #' || p_order_id::text || ' has been marked as PLACED.';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
