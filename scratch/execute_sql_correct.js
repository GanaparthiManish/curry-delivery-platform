const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error("Usage: node execute_sql_correct.js <sql_file>");
        return;
    }
    console.log("Reading SQL from:", filePath);
    const sql = fs.readFileSync(filePath, 'utf8');

    console.log("Executing SQL...");
    // Let's try rpc 'exec_sql' with parameter 'sql'
    const { data, error } = await supabase.rpc('exec_sql', { sql });

    if (error) {
        console.error("RPC ERROR:", JSON.stringify(error, null, 2));
        // Try with p_query parameter
        console.log("Trying with p_query...");
        const { data: d2, error: e2 } = await supabase.rpc('exec_sql', { p_query: sql });
        if (e2) {
            console.error("P_QUERY ERROR:", JSON.stringify(e2, null, 2));
        } else {
            console.log("SUCCESS with p_query!", d2);
        }
    } else {
        console.log("SUCCESS with sql!", data);
    }
}

run();
