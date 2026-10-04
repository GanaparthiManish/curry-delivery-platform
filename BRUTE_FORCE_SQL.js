const https = require('https');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const sql = fs.readFileSync(process.argv[2], 'utf8');

const rpcs = ['exec_sql', 'exec_sql_v1', 'execute_sql', 'sql', 'query', 'admin_query'];
const params = ['sql', 'sql_query', 'p_query', 'query'];

async function tryAll() {
    for (const rpc of rpcs) {
        for (const param of params) {
            console.log(`>>> Trying RPC: ${rpc} with param: ${param}...`);
            const data = JSON.stringify({ [param]: sql });
            
            const success = await new Promise((resolve) => {
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

                const req = https.request(options, (res) => {
                    let body = '';
                    res.on('data', (d) => body += d);
                    res.on('end', () => {
                        if (res.statusCode >= 200 && res.statusCode < 300) {
                            console.log(`✅ SUCCESS with ${rpc}(${param})!`);
                            console.log("Response:", body);
                            resolve(true);
                        } else {
                            // console.log(`❌ FAILED ${rpc}(${param}): ${res.statusCode} ${body}`);
                            resolve(false);
                        }
                    });
                });
                req.on('error', () => resolve(false));
                req.write(data);
                req.end();
            });

            if (success) return;
        }
    }
    console.log("❌ All attempts failed.");
}

tryAll();
