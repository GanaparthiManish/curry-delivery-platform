const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('https://dxqcruvarqgnscenixzf.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s');

async function debugLinks() {
    console.log("--- DEBUGGING VENDOR-PRODUCT LINKS ---");

    // 1. Get all product vendor_ids
    const { data: products } = await supabase.from('products').select('name, vendor_id');
    const productVendorIds = [...new Set(products.map(p => p.vendor_id).filter(id => id))];
    console.log("Unique Vendor IDs on Products:", productVendorIds);

    // 2. Check which of these exist in vendors table
    const { data: existingVendors } = await supabase.from('vendors').select('id, name').in('id', productVendorIds);
    const existingIds = existingVendors.map(v => v.id);
    console.log("Existing Vendor IDs:", existingIds);

    const missingIds = productVendorIds.filter(id => !existingIds.includes(id));
    console.log("MISSING Vendor IDs (Broken links):", missingIds);

    // 3. Count products per vendor
    const counts = {};
    products.forEach(p => {
        counts[p.vendor_id] = (counts[p.vendor_id] || 0) + 1;
    });
    console.log("Product counts per vendor ID:", counts);
}

debugLinks();
