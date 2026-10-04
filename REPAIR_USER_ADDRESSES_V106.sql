-- 🛡️ SAVED ADDRESSES STABILITY (V106)
-- 🎯 MISSION: Fix blank "Saved Addresses" and ensure real-time persistence.
-- 🚀 TARGET: Synchronize 'user_addresses' table with Flutter UI.

BEGIN;

-- 1. 🛡️ RE-CREATE OR REPAIR USER_ADDRESSES TABLE
-- We use TEXT for user_id to support our SMS-Auth/Stable-UID system.
CREATE TABLE IF NOT EXISTS public.user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    label TEXT, -- Home, Work, Other
    address_line1 TEXT,
    address_line2 TEXT,
    house_number TEXT,
    pincode TEXT,
    phone TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 🛡️ ENSURE TYPE NEUTRALITY (TEXT ID)
-- If it was UUID, we alter it.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'user_addresses' AND column_name = 'user_id' AND data_type = 'uuid'
    ) THEN
        ALTER TABLE public.user_addresses ALTER COLUMN user_id TYPE TEXT;
    END IF;
END $$;

-- 3. 🛡️ ADD FALLBACK COLUMNS (In case app uses 'address_line' or 'title')
-- We use triggers to keep them in sync if they exist.
ALTER TABLE public.user_addresses ADD COLUMN IF NOT EXISTS address_line TEXT;
ALTER TABLE public.user_addresses ADD COLUMN IF NOT EXISTS title TEXT;

CREATE OR REPLACE FUNCTION public.sync_address_columns()
RETURNS TRIGGER AS $$
BEGIN
    -- Sync address_line1 to address_line for compatibility
    NEW.address_line := COALESCE(NEW.address_line1, NEW.address_line);
    NEW.address_line1 := COALESCE(NEW.address_line1, NEW.address_line);
    
    -- Sync label to title for compatibility
    NEW.title := COALESCE(NEW.label, NEW.title);
    NEW.label := COALESCE(NEW.label, NEW.title);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_sync_address_columns ON public.user_addresses;
CREATE TRIGGER tr_sync_address_columns
BEFORE INSERT OR UPDATE ON public.user_addresses
FOR EACH ROW EXECUTE PROCEDURE public.sync_address_columns();

-- 4. 🛡️ CLEANUP GHOST DATA
-- If user has addresses with no text, they are likely old test data.
-- DELETE FROM public.user_addresses WHERE address_line1 IS NULL AND address_line IS NULL;

-- 5. 🛡️ PERMISSIONS
GRANT ALL ON public.user_addresses TO anon, authenticated, service_role;

COMMIT;

-- 🔄 RELOAD SCHEMA
NOTIFY pgrst, 'reload schema';
SELECT '✅ SAVED ADDRESSES TABLE REPAIRED!' as status;
