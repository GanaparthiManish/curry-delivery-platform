-- 🔓 NUCLEAR SECURITY RESET: Unblocking all Admin mutations for Anon Key
-- This script disables RLS on the core tables to ensure the Admin Panel functions without Service Role keys.

-- 1. CATEGORIES
ALTER TABLE categories DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for everyone" ON categories;
CREATE POLICY "Allow all for everyone" ON categories FOR ALL USE (true) WITH CHECK (true);

-- 2. PRODUCTS
ALTER TABLE products DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for everyone" ON products;
CREATE POLICY "Allow all for everyone" ON products FOR ALL USE (true) WITH CHECK (true);

-- 3. VENDORS
ALTER TABLE vendors DISABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all for everyone" ON vendors;
CREATE POLICY "Allow all for everyone" ON vendors FOR ALL USE (true) WITH CHECK (true);

-- 4. Give permissions to anon/authenticated roles just in case
GRANT ALL ON categories TO anon, authenticated, postgres, service_role;
GRANT ALL ON products TO anon, authenticated, postgres, service_role;
GRANT ALL ON vendors TO anon, authenticated, postgres, service_role;
