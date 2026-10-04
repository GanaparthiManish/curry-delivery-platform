-- ============================================================
-- FIX: app_settings RLS + Realtime Publication
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. Create table if it doesn't exist yet
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Drop ALL existing policies to avoid conflicts
DROP POLICY IF EXISTS "app_settings_read" ON app_settings;
DROP POLICY IF EXISTS "app_settings_admin_write" ON app_settings;
DROP POLICY IF EXISTS "Allow admin read app_settings" ON app_settings;
DROP POLICY IF EXISTS "Allow admin write app_settings" ON app_settings;
DROP POLICY IF EXISTS "app_settings_read_all" ON app_settings;
DROP POLICY IF EXISTS "app_settings_insert_all" ON app_settings;
DROP POLICY IF EXISTS "app_settings_update_all" ON app_settings;
DROP POLICY IF EXISTS "app_settings_delete_all" ON app_settings;

-- 3. Enable RLS
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- 4. Allow EVERYONE to READ (customer app needs it)
CREATE POLICY "app_settings_read_all"
  ON app_settings FOR SELECT
  USING (true);

-- 5. Allow authenticated users to INSERT (for admin upsert)
CREATE POLICY "app_settings_insert_all"
  ON app_settings FOR INSERT
  WITH CHECK (true);

-- 6. Allow authenticated users to UPDATE
CREATE POLICY "app_settings_update_all"
  ON app_settings FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- 7. Seed default system_config if not present
INSERT INTO app_settings (key, value, updated_at)
VALUES (
  'system_config',
  '{
    "platformName": "UNIV Foods",
    "supportEmail": "support@univfoods.in",
    "supportPhone": "+919940407600",
    "emergencyPhone": "100",
    "deliveryRadius": 15,
    "autoAssignRiders": true,
    "codEnabled": true,
    "maxCodValue": 2000,
    "deliveryFee": 0,
    "platformFee": 0,
    "taxRate": 0
  }',
  now()
)
ON CONFLICT (key) DO NOTHING;

-- 8. Enable Realtime for app_settings (so Flutter app gets live updates)
ALTER TABLE app_settings REPLICA IDENTITY FULL;

-- Add to realtime publication
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'app_settings'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE app_settings;
  END IF;
END;
$$;

-- Verify
SELECT key, value, updated_at FROM app_settings WHERE key = 'system_config';
