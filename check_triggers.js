const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    console.log("Checking triggers on orders table...");
    const { data, error } = await supabase.rpc('exec_sql', { 
        sql: `
            SELECT trigger_name, action_statement 
            FROM information_schema.triggers 
            WHERE event_object_table = 'orders';
        `
    });

    if (error) {
        console.error("RPC ERROR:", error);
    } else {
        console.log("Triggers:", JSON.stringify(data, null, 2));
    }
}
run();
