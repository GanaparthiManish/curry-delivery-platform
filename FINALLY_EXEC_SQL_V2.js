
const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error("Usage: node FINALLY_EXEC_SQL_V2.js <sql_file>");
        return;
    }
    const sql = fs.readFileSync(filePath, 'utf8');

    console.log("Executing SQL...");
    const params = ['sql', 'query', 'p_query', 'sql_query'];

    for (const p of params) {
        console.log(`Trying with param: ${p}`);
        const { data, error } = await supabase.rpc('exec_sql', { [p]: sql });
        if (!error) {
            console.log(`SUCCESS with ${p}!`);
            console.log(data);
            return;
        } else {
            console.log(`Error with ${p}:`, error.message);
        }
    }
}

run();
