CREATE OR REPLACE FUNCTION public.confirm_upi_payment(p_order_id UUID, p_payment_id TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.orders
    SET status = 'placed',
        order_status = 'placed',
        payment_status = 'SUCCESS',
        payment_state = 'SUCCESS',
        payment_id = p_payment_id,
        updated_at = NOW()
    WHERE id = p_order_id;
END;
$$;
