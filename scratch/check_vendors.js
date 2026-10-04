const { createClient } = require('../temp_node/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    console.log("=== VENDORS IN DB ===");
    const { data: vendors, error: vErr } = await supabase.from('vendors').select('id, name, latitude, longitude, status, is_active, is_open');
    if (vErr) {
        console.error(vErr);
    } else {
        console.log(`Found ${vendors.length} vendors:`);
        vendors.forEach(v => {
            console.log(`- ${v.name}: Lat=${v.latitude}, Lng=${v.longitude}, Status=${v.status}, Active=${v.is_active}, Open=${v.is_open}`);
        });
    }

    console.log("\n=== LATEST ORDERS IN DB ===");
    const { data: orders, error: oErr } = await supabase.from('orders').select('id, customer_id, vendor_id, delivery_address, delivery_lat, delivery_lng, vendor_lat, vendor_lng, rider_lat, rider_lng, rider_id, status').order('created_at', { ascending: false }).limit(3);
    if (oErr) {
        console.error(oErr);
    } else {
        console.log(JSON.stringify(orders, null, 2));
    }
}

run();
