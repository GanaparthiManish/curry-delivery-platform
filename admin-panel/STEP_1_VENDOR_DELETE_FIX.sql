-- ✅ STEP 1: Enable Cascading Deletes for Vendors
-- This allows deleting a vendor to automatically remove their products and orders.

-- Drop existing constraints
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_vendor_id_fkey;
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_vendor_id_fkey;

-- Re-add with CASCADE
ALTER TABLE public.products 
  ADD CONSTRAINT products_vendor_id_fkey 
  FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) 
  ON DELETE CASCADE;

ALTER TABLE public.orders 
  ADD CONSTRAINT orders_vendor_id_fkey 
  FOREIGN KEY (vendor_id) REFERENCES public.vendors(id) 
  ON DELETE SET NULL; -- Keep orders but disconnect from vendor for history

-- ✅ STEP 2: Ensure RLS is disabled for this test phase
ALTER TABLE public.vendors DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.products DISABLE ROW LEVEL SECURITY;
GRANT ALL ON public.vendors TO anon, authenticated, public;
GRANT ALL ON public.products TO anon, authenticated, public;
