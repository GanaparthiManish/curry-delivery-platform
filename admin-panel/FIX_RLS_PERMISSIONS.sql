-- 🛑 CATEGORIES: Enable ALL access for authenticated users (Admin)
DROP POLICY IF EXISTS "Allow all for authenticated categories" ON categories;
CREATE POLICY "Allow all for authenticated categories" ON categories
    FOR ALL 
    TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read categories" ON categories;
CREATE POLICY "Allow public read categories" ON categories
    FOR SELECT 
    TO public
    USING (true);

-- 🛑 PRODUCTS: Enable ALL access for authenticated users
DROP POLICY IF EXISTS "Allow all for authenticated products" ON products;
CREATE POLICY "Allow all for authenticated products" ON products
    FOR ALL 
    TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read products" ON products;
CREATE POLICY "Allow public read products" ON products
    FOR SELECT 
    TO public
    USING (true);

-- 🛑 VENDORS: Enable ALL access for authenticated users
DROP POLICY IF EXISTS "Allow all for authenticated vendors" ON vendors;
CREATE POLICY "Allow all for authenticated vendors" ON vendors
    FOR ALL 
    TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public read vendors" ON vendors;
CREATE POLICY "Allow public read vendors" ON vendors
    FOR SELECT 
    TO public
    USING (true);

-- Ensure Realtime is enabled
ALTER PUBLICATION supabase_realtime ADD TABLE categories;
ALTER PUBLICATION supabase_realtime ADD TABLE products;
ALTER PUBLICATION supabase_realtime ADD TABLE vendors;
