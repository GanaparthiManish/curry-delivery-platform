const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function run() {
    const filePath = process.argv[2];
    if (!filePath) {
        console.error("Usage: node run_query_fetch.js <sql_file>");
        return;
    }
    const sql = fs.readFileSync(filePath, 'utf8');

    console.log("Executing query...");
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
            method: 'POST',
            headers: {
                'apikey': serviceKey,
                'Authorization': `Bearer ${serviceKey}`,
                'Content-Type': 'application/json',
                'Prefer': 'params=single-object'
            },
            body: JSON.stringify({ sql })
        });
        const text = await res.text();
        if (res.ok) {
            console.log("Query Results:");
            console.log(text);
        } else {
            console.error("Error executing query:", res.status, text);
            // Try with p_query parameter just in case
            console.log("Retrying with p_query parameter...");
            const res2 = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
                method: 'POST',
                headers: {
                    'apikey': serviceKey,
                    'Authorization': `Bearer ${serviceKey}`,
                    'Content-Type': 'application/json',
                    'Prefer': 'params=single-object'
                },
                body: JSON.stringify({ p_query: sql })
            });
            const text2 = await res2.text();
            if (res2.ok) {
                console.log("Query Results (p_query):");
                console.log(text2);
            } else {
                console.error("Error executing query (p_query):", res2.status, text2);
            }
        }
    } catch (e) {
        console.error("Fetch error:", e);
    }
}

run();
