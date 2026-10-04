import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function listProducts() {
    const { data: vendors } = await supabase.from('vendors').select('id, name').eq('name', 'Samskruthi Curry Point');
    if (!vendors || vendors.length === 0) {
        console.log("Vendor not found");
        return;
    }
    const vendorId = vendors[0].id;
    console.log(`Found Vendor: ${vendors[0].name} (${vendorId})`);

    const { data: products, error } = await supabase.from('products').select('*').eq('vendor_id', vendorId);
    if (error) {
        console.error("Error fetching products:", error);
        return;
    }
    
    console.log(`Found ${products.length} products:`);
    products.forEach(p => {
        console.log(`- [${p.id}] ${p.name}: ₹${p.price} (Available: ${p.is_available})`);
    });
}

listProducts();
