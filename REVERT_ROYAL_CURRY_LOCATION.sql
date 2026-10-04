-- 🛠️ REVERT: Restore Royal Curry to its original Tamil Nadu location
-- I moved it to Hyderabad by mistake. This restores the admin-set coordinates.

UPDATE public.vendors 
SET 
    latitude  = 9.56450793004939,
    longitude = 77.6908580799924
WHERE name ILIKE '%Royal Curry%';

-- Verify the fix
SELECT id, name, latitude, longitude FROM public.vendors WHERE name ILIKE '%Royal Curry%';
