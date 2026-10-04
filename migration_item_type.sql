ALTER TABLE public.products ADD COLUMN IF NOT EXISTS item_type TEXT DEFAULT 'fixed_vendor';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT false;
UPDATE public.products SET item_type = 'popular' WHERE is_popular = true;

ALTER TABLE public.foods ADD COLUMN IF NOT EXISTS item_type TEXT DEFAULT 'fixed_vendor';
ALTER TABLE public.foods ADD COLUMN IF NOT EXISTS is_popular BOOLEAN DEFAULT false;
UPDATE public.foods SET item_type = 'popular' WHERE is_popular = true;
