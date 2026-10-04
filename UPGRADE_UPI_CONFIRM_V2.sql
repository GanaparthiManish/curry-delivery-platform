-- 🚀 SUPER ROBUST UPI CONFIRMATION (v2)
-- MISSION: Ensure orders transition to PLACED status immediately after payment success.
-- This function handles status, payment_status, and notifies the realtime layer.

CREATE OR REPLACE FUNCTION public.confirm_upi_payment_v2(p_order_id UUID, p_payment_id TEXT)
RETURNS TEXT AS $$
BEGIN
    -- 1. Attempt to update the order
    UPDATE public.orders
    SET 
        status = 'PLACED',          -- Main status field
        order_status = 'PLACED',    -- Detailed status field
        payment_status = 'SUCCESS',
        payment_state = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 2. Check if the update actually happened
    IF NOT FOUND THEN
        RETURN 'ERROR: Order not found';
    END IF;

    RETURN 'SUCCESS: Order marked as PLACED';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.confirm_upi_payment_v2(UUID, TEXT) TO anon, authenticated, service_role;

-- Overwrite legacy function to point to same logic if needed, 
-- but we will update the app to use V2.
CREATE OR REPLACE FUNCTION public.confirm_upi_payment(p_order_id UUID, p_payment_id TEXT)
RETURNS void AS $$
BEGIN
    PERFORM public.confirm_upi_payment_v2(p_order_id, p_payment_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
