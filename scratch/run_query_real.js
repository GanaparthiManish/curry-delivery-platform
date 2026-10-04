const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error("Usage: node run_query_real.js <sql_file>");
        return;
    }
    const sql = fs.readFileSync(filePath, 'utf8');

    console.log("Executing query...");
    const { data, error } = await supabase.rpc('exec_sql', { sql });
    if (error) {
        console.error("Error executing query:", error);
    } else {
        console.log("Query Results:");
        console.log(JSON.stringify(data, null, 2));
    }
}

run();
