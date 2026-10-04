SELECT 
    schemaname, 
    tablename, 
    policyname, 
    permissive, 
    roles, 
    cmd, 
    qual, 
    with_check 
FROM pg_policies 
WHERE tablename = 'orders';

SELECT relname, relrowsecurity 
FROM pg_class 
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace 
WHERE relname = 'orders' AND nspname = 'public';
