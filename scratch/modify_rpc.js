const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceRoleKey);

const sql = `
CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION, 
    p_lng DOUBLE PRECISION, 
    p_category_id TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE 
    result JSON;
BEGIN
    SELECT json_agg(item_data) INTO result FROM (
        SELECT 
            p.*, 
            v.name as vendor_name,
            c.name as category_name, 
            (SELECT row_to_json(tv) FROM public.get_trusted_vendor_for_item_v2(p.id::text, p_lat, p_lng) tv) as trusted_vendor
        FROM public.products p 
        JOIN public.vendors v ON p.vendor_id = v.id
        LEFT JOIN public.categories c ON p.category_id::text = c.id::text
        WHERE p.is_active = true 
          AND (p_category_id IS NULL OR p_category_id = '' OR p.category_id::text = p_category_id OR c.name ILIKE p_category_id)
          -- 🌍 5KM STRICT RADIUS (Approximate distance in KM)
          AND (6371 * acos(
              cos(radians(p_lat)) * cos(radians(v.latitude)) * 
              cos(radians(v.longitude) - radians(p_lng)) + 
              sin(radians(p_lat)) * sin(radians(v.latitude))
          )) <= 5.0
        ORDER BY p.created_at DESC
        LIMIT 200
    ) item_data WHERE item_data.trusted_vendor IS NOT NULL;
    
    RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;
`;

async function run() {
  try {
    const res = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql_v1`, {
      method: 'POST',
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': `Bearer ${serviceRoleKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ sql_query: sql })
    });
    console.log("Status:", res.status);
    console.log("Response:", await res.text());
  } catch (e) {
    console.error(e);
  }
}

run();
