const { createClient } = require('@supabase/supabase-js');
const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(url, serviceKey);

async function run() {
    console.log("Checking for exec_sql RPC...");
    const { data: list, error: listErr } = await supabase.rpc('exec_sql', { sql: 'SELECT 1' });
    if (listErr) {
        console.log("exec_sql(sql) failed:", listErr.message);
        const { data: list2, error: listErr2 } = await supabase.rpc('exec_sql', { p_query: 'SELECT 1' });
        if (listErr2) {
            console.log("exec_sql(p_query) failed:", listErr2.message);
        } else {
            console.log("exec_sql(p_query) WORKS!");
        }
    } else {
        console.log("exec_sql(sql) WORKS!");
    }
}
run();
