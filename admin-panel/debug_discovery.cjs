const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('https://dxqcruvarqgnscenixzf.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s');

async function debugDiscovery() {
    const lat = 17.44;
    const lng = 78.35;

    console.log(`--- DEBUGGING DISCOVERY ---`);

    // 1. Get categories
    const { data: cats } = await supabase.from('categories').select('id, name');
    console.log("Categories:", cats);

    // 2. Check if products have categories
    const { data: products } = await supabase.from('products').select('id, name, category_id, is_active').limit(10);
    console.log("Products with Categories:", products);

    // 3. Test RPC with NULL category
    console.log("--- TESTING RPC get_popular_near_you_v2 (NO CATEGORY) ---");
    const { data: rpcData, error: rpcErr } = await supabase.rpc('get_popular_near_you_v2', {
        p_lat: lat,
        p_lng: lng
    });
    console.log("RPC Result (No Category):", JSON.stringify(rpcData, null, 2) || rpcErr);

    // 4. Check a specific category (e.g. Biryani)
    const biryaniCat = cats.find(c => c.name.includes('Biryani'));
    if (biryaniCat) {
        console.log(`--- TESTING RPC FOR CATEGORY: ${biryaniCat.name} (${biryaniCat.id}) ---`);
        const { data: rpcCatData } = await supabase.rpc('get_popular_near_you_v2', {
            p_lat: lat,
            p_lng: lng,
            p_category_id: biryaniCat.id
        });
        console.log("RPC Result (Category):", rpcCatData?.length || 0, "items");
    }
}

debugDiscovery();
