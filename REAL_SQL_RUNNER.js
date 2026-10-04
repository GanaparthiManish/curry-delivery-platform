
const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const fs = require('fs');

async function run() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error("Usage: node REAL_SQL_RUNNER.js <file.sql>");
        return;
    }
    const sql = fs.readFileSync(filePath, 'utf8');

    // We know 'exec_sql' exists from probing, we just need the right param.
    const params = ['sql', 'query', 'p_query', 'sql_query'];

    for (const p of params) {
        console.log(`Trying exec_sql with param: ${p}`);
        const res = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
            method: 'POST',
            headers: {
                'apikey': serviceKey,
                'Authorization': `Bearer ${serviceKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ [p]: sql })
        });

        const body = await res.text();
        if (res.ok) {
            console.log(`SUCCESS with param: ${p}!`);
            console.log(body);
            return;
        } else {
            console.log(`Failed with param ${p}: ${res.status} ${body}`);
        }
    }
}

run();
