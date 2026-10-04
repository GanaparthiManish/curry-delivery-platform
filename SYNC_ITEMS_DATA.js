
const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function syncData() {
    console.log("Starting data sync with service_role...");

    // 1. Fetch all products
    console.log("Fetching products...");
    const productsRes = await fetch(`${supabaseUrl}/rest/v1/products`, {
        headers: {
            'apikey': serviceKey,
            'Authorization': `Bearer ${serviceKey}`
        }
    });
    const products = await productsRes.json();
    console.log(`Found ${products.length} products.`);

    // 2. Set is_popular = true for all active products
    console.log("Updating is_popular flag...");
    const updateRes = await fetch(`${supabaseUrl}/rest/v1/products?is_active=eq.true`, {
        method: 'PATCH',
        headers: {
            'apikey': serviceKey,
            'Authorization': `Bearer ${serviceKey}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ is_popular: true })
    });
    console.log("Update status:", updateRes.status);

    // 3. Populate vendor_foods
    console.log("Populating vendor_foods...");
    const vendorFoods = products.map(p => ({
        vendor_id: p.vendor_id,
        food_id: p.id,
        price: p.price,
        is_available: p.is_available
    }));

    // Chunk the inserts to avoid payload size limits
    for (let i = 0; i < vendorFoods.length; i += 50) {
        const chunk = vendorFoods.slice(i, i + 50);
        const vfRes = await fetch(`${supabaseUrl}/rest/v1/vendor_foods`, {
            method: 'POST',
            headers: {
                'apikey': serviceKey,
                'Authorization': `Bearer ${serviceKey}`,
                'Content-Type': 'application/json',
                'Prefer': 'resolution=merge-duplicates'
            },
            body: JSON.stringify(chunk)
        });
        console.log(`Chunk ${i / 50 + 1} insert status:`, vfRes.status);
    }

    // 4. Fix Vendor Status (Set to ONLINE)
    console.log("Setting all active vendors to ONLINE status...");
    const vendorRes = await fetch(`${supabaseUrl}/rest/v1/vendors?is_active=eq.true`, {
        method: 'PATCH',
        headers: {
            'apikey': serviceKey,
            'Authorization': `Bearer ${serviceKey}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ status: 'ONLINE', is_open: true })
    });
    console.log("Vendor status update:", vendorRes.status);

    console.log("Sync complete!");
}

syncData();
