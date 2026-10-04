const https = require('https');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function runSql() {
    const filePath = process.argv[2] || './FIX_SHOP_CLOSED_V61.sql';
    const sql = fs.readFileSync(filePath, 'utf8');

    async function tryRpc(paramName) {
        return new Promise((resolve) => {
            const data = JSON.stringify({
                [paramName]: sql
            });

            const options = {
                hostname: supabaseUrl.replace('https://', ''),
                port: 443,
                path: '/rest/v1/rpc/exec_sql',
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'apikey': serviceKey,
                    'Authorization': 'Bearer ' + serviceKey,
                    'Content-Length': Buffer.byteLength(data)
                }
            };

            const req = https.request(options, (res) => {
                let responseBody = '';
                res.on('data', (chunk) => responseBody += chunk);
                res.on('end', () => {
                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        console.log(`SQL executed successfully with parameter '${paramName}'!`);
                        resolve(true);
                    } else {
                        console.error(`Error with parameter '${paramName}':`, res.statusCode, responseBody);
                        resolve(false);
                    }
                });
            });

            req.on('error', (error) => {
                console.error(`Request Error with parameter '${paramName}':`, error);
                resolve(false);
            });

            req.write(data);
            req.end();
        });
    }

    const successWithSql = await tryRpc('sql');
    if (!successWithSql) {
        console.log("Retrying with 'p_query'...");
        await tryRpc('p_query');
    }
}

runSql();
