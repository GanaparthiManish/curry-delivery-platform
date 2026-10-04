-- DATABASE PERFORMANCE INDEXES v103
-- 🎯 MISSION: Fix "Loading Forever" by making order queries 100x faster.

BEGIN;

-- 🛡️ 1. INDEXES FOR ORDERS TABLE
-- customer_id is the main lookup field in OrdersScreen
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON public.orders(customer_id);
-- vendor_id is used in the join for the tracking view
CREATE INDEX IF NOT EXISTS idx_orders_vendor_id ON public.orders(vendor_id);
-- created_at is used for sorting
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);

-- 🛡️ 2. INDEXES FOR JOIN TABLES (Foreign Keys)
-- These are used in the LEFT JOINs of the stabilized view
CREATE INDEX IF NOT EXISTS idx_vendors_id_text ON public.vendors((id::text));
CREATE INDEX IF NOT EXISTS idx_riders_id_text ON public.delivery_riders((id::text));

-- 🛡️ 3. FUNCTIONAL INDEXES FOR IDENTITIES
-- Since we use sms_auth_91... variants, indexing phone in profiles is key
CREATE INDEX IF NOT EXISTS idx_customer_profiles_phone ON public.customer_profiles(phone);

COMMIT;

SELECT 'INDEXES CREATED: Queries should now be significantly faster' as status;
