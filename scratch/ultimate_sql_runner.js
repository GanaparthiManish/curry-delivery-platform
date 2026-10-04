const https = require('https');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const sql = fs.readFileSync('PERMANENT_STABILITY_FIX_V100.sql', 'utf8');

async function run() {
    // Try to find ANY rpc that can execute this. 
    // We'll try the ones we saw in the file list but maybe they were deleted.
    const rpcs = ['exec_sql', 'run_sql_native', 'execute_query', 'admin_exec'];
    
    for (const rpc of rpcs) {
        console.log(`Trying RPC: ${rpc}`);
        const data = JSON.stringify({ sql: sql, sql_query: sql, query: sql });
        
        const options = {
            hostname: 'dxqcruvarqgnscenixzf.supabase.co',
            port: 443,
            path: `/rest/v1/rpc/${rpc}`,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'apikey': serviceKey,
                'Authorization': 'Bearer ' + serviceKey,
                'Content-Length': Buffer.byteLength(data)
            }
        };

        const res = await new Promise((resolve) => {
            const req = https.request(options, (res) => {
                let body = '';
                res.on('data', (d) => body += d);
                res.on('end', () => resolve({ status: res.statusCode, body }));
            });
            req.on('error', (e) => resolve({ status: 500, body: e.message }));
            req.write(data);
            req.end();
        });

        if (res.status >= 200 && res.status < 300) {
            console.log(`✅ SUCCESS with ${rpc}!`);
            console.log(res.body);
            return;
        } else {
            console.log(`❌ Failed ${rpc}: ${res.status} ${res.body}`);
        }
    }
}

run();
