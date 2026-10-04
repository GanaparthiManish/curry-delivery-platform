BEGIN;

-- Ensure vendor_foods table is fully populated from existing products
INSERT INTO public.vendor_foods (vendor_id, food_id, price, is_available)
SELECT vendor_id::TEXT, id::TEXT, price::NUMERIC, COALESCE(is_available, true)
FROM public.products
WHERE vendor_id IS NOT NULL AND id IS NOT NULL
ON CONFLICT (vendor_id, food_id) DO NOTHING;

-- Log number of rows inserted/updated
SELECT count(*) FROM public.vendor_foods;

COMMIT;
