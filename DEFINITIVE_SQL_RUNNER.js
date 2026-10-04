const fetch = (...args) => import('node-fetch').then(({ default: fetch }) => fetch(...args));
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function runSql(sql) {
    const attempts = [
        { name: 'exec_sql', param: 'sql' },
        { name: 'exec_sql', param: 'p_query' },
        { name: 'exec_sql_v1', param: 'sql_query' },
        { name: 'exec_sql_v1', param: 'sql' },
        { name: 'execute_sql', param: 'sql' },
        { name: 'run_sql', param: 'sql' }
    ];

    for (const attempt of attempts) {
        console.log(`>>> Trying RPC: ${attempt.name} with param: ${attempt.param}...`);
        try {
            const res = await fetch(`${supabaseUrl}/rest/v1/rpc/${attempt.name}`, {
                method: 'POST',
                headers: {
                    'apikey': serviceKey,
                    'Authorization': `Bearer ${serviceKey}`,
                    'Content-Type': 'application/json',
                    'Prefer': 'params=single-object'
                },
                body: JSON.stringify({ [attempt.param]: sql })
            });
            const text = await res.text();
            if (res.ok) {
                console.log(`✅ SUCCESS with ${attempt.name}!`);
                console.log(text);
                return true;
            } else {
                console.log(`❌ FAILED: ${res.status} ${text}`);
            }
        } catch (e) {
            console.log(`❌ ERROR: ${e.message}`);
        }
    }
    return false;
}

const sqlFile = process.argv[2] || 'URGENT_REPAIR_V1.sql';
const sql = fs.readFileSync(sqlFile, 'utf8');
runSql(sql);
