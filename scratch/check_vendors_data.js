const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function query(sql) {
    const data = JSON.stringify({ sql: sql });
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'dxqcruvarqgnscenixzf.supabase.co',
            port: 443,
            path: '/rest/v1/rpc/exec_sql',
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'apikey': serviceKey,
                'Authorization': 'Bearer ' + serviceKey,
            }
        };
        const req = https.request(options, (res) => {
            let body = '';
            res.on('data', (d) => body += d);
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    resolve(JSON.parse(body));
                } else {
                    reject(new Error(`Status ${res.statusCode}: ${body}`));
                }
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

async function run() {
    try {
        console.log(">>> Checking Vendors...");
        const vendors = await query("SELECT id, name, status, latitude, longitude FROM vendors");
        console.log("Vendors:", JSON.stringify(vendors, null, 2));

        console.log("\n>>> Checking Products Count...");
        const productsCount = await query("SELECT count(*) FROM products WHERE is_active = true");
        console.log("Active Products Count:", productsCount);

        console.log("\n>>> Checking Categories...");
        const categories = await query("SELECT id, name FROM categories");
        console.log("Categories:", categories);

    } catch (e) {
        console.error("Error:", e.message);
    }
}

run();
