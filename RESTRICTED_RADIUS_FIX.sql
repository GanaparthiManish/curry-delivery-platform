
-- 🌍 GLOBAL RADIUS BOOST: Set delivery limits to 15km
UPDATE public.vendors 
SET delivery_radius_km = 15,
    radius_km = 15
WHERE id IS NOT NULL;

-- 🛡️ VIEW STABILIZATION: Ensure order_tracking_stabilized_v1 reflects unpaid status correctly
-- (Actually, the view already selects everything, filtering should happen in the apps or a filtered view)

-- If the user wants to *strictly* only show successful orders:
CREATE OR REPLACE VIEW public.active_placed_orders_v1 AS
SELECT * FROM public.orders
WHERE 
    -- COD is always showing
    (payment_method = 'COD')
    OR 
    -- UPI/ONLINE successfully paid
    (payment_method IN ('UPI', 'ONLINE', 'RAZORPAY', 'razorpay') AND (payment_status IN ('SUCCESS', 'PAID', 'COMPLETED', 'success', 'paid')))
    OR
    -- 🚀 INSTANT SYNC: Show any UPI order in the first 15 minutes so it's not missing while syncing
    (payment_method IN ('UPI', 'ONLINE', 'RAZORPAY', 'razorpay') AND created_at > (NOW() - INTERVAL '15 minutes'));

GRANT SELECT ON public.active_placed_orders_v1 TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
