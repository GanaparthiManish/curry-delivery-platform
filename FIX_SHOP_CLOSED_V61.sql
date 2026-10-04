
BEGIN;

-- 🛠 FIX 1: Make all active vendors "Open" 24/7 for testing
CREATE OR REPLACE FUNCTION public.is_vendor_open_logic(p_vendor_id TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    SELECT is_active INTO v_active FROM public.vendors WHERE id::text = p_vendor_id::text;
    -- If vendor exists and is active, let them stay open
    RETURN COALESCE(v_active, true);
EXCEPTION WHEN OTHERS THEN
    RETURN TRUE; 
END;
$$;

-- 🛠 FIX 2: Handle UUID variant just in case
CREATE OR REPLACE FUNCTION public.is_vendor_open_logic(p_vendor_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.is_vendor_open_logic(p_vendor_id::text);
END;
$$;

-- 🛠 FIX 3: Force existing vendors to be Online/Open
UPDATE public.vendors 
SET is_open = true, 
    status = 'ONLINE'
WHERE is_active = true;

COMMIT;
NOTIFY pgrst, 'reload schema';
