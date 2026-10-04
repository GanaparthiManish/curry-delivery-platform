-- Add is_popular flag to products
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT false;
-- Temporary: set all existing active items to popular so the home feed isn't empty!
UPDATE public.products SET is_popular = true WHERE is_active = true;

-- Create vendor_foods table to map items to vendors with specific prices/availability
CREATE TABLE IF NOT EXISTS public.vendor_foods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vendor_id TEXT REFERENCES public.vendors(id) ON DELETE CASCADE,
    food_id TEXT REFERENCES public.products(id) ON DELETE CASCADE,
    price NUMERIC NOT NULL,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(vendor_id, food_id)
);

-- Update get_popular_items_feed to only return popular items
CREATE OR REPLACE FUNCTION public.get_popular_items_feed(p_lat double precision, p_lng double precision)
RETURNS TABLE(
    id text, 
    name character varying, 
    description text, 
    image_url character varying, 
    price numeric, 
    is_veg boolean, 
    is_popular boolean, 
    trusted_vendor jsonb
)
LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.name,
    p.description,
    p.image_url,
    p.price,
    p.is_veg,
    p.is_popular,
    -- Simple trusted vendor logic: gets the cheapest available vendor for this popular product within 10km
    (
      SELECT jsonb_build_object(
        'vendor_id', v.id,
        'vendor_name', v.name,
        'price', vf.price,
        'rating', v.rating,
        'distance', (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude))))
      )
      FROM public.vendor_foods vf
      JOIN public.vendors v ON v.id = vf.vendor_id
      WHERE vf.food_id = p.id 
        AND vf.is_available = true 
        AND v.status = 'ONLINE'
        AND v.is_open = true
        AND (6371 * acos(cos(radians(p_lat)) * cos(radians(v.latitude)) * cos(radians(v.longitude) - radians(p_lng)) + sin(radians(p_lat)) * sin(radians(v.latitude)))) <= 10
      ORDER BY vf.price ASC
      LIMIT 1
    ) as trusted_vendor
  FROM public.products p
  WHERE p.is_active = true AND p.is_popular = true;
END;
$function$;
