const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    console.log(">>> Fetching vendors...");
    const { data, error } = await supabase.from('vendors').select('id, name, status, latitude, longitude');
    if (error) {
        console.error("Error:", error.message);
        return;
    }
    console.log("Vendors:", JSON.stringify(data, null, 2));

    console.log("\n>>> Fetching active products count...");
    const { count, error: countErr } = await supabase.from('products').select('*', { count: 'exact', head: true }).eq('is_active', true);
    if (countErr) {
        console.error("Count Error:", countErr.message);
    } else {
        console.log("Active Products Count:", count);
    }
}

run();
