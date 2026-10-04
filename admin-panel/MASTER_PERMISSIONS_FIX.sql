-- ✅ FIXED: Correct PostgreSQL RLS syntax (USING not USE)
-- Run this in Supabase SQL Editor

-- 1. DISABLE RLS completely on all 3 tables
ALTER TABLE IF EXISTS categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS products DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS vendors DISABLE ROW LEVEL SECURITY;

-- 2. Explicit Grants for all roles
GRANT ALL ON categories TO public, anon, authenticated;
GRANT ALL ON products TO public, anon, authenticated;
GRANT ALL ON vendors TO public, anon, authenticated;
