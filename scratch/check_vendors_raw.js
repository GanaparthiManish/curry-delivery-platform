const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function get(path) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'dxqcruvarqgnscenixzf.supabase.co',
            port: 443,
            path: `/rest/v1/${path}`,
            method: 'GET',
            headers: {
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
        req.end();
    });
}

async function run() {
    try {
        console.log(">>> Fetching vendors...");
        const vendors = await get('vendors?select=id,name,status,latitude,longitude');
        console.log("Vendors:", JSON.stringify(vendors, null, 2));

        console.log("\n>>> Fetching active products...");
        const products = await get('products?select=id,name,is_active,is_available,is_popular,item_type&is_active=eq.true&limit=5');
        console.log("Active Products (Sample):", JSON.stringify(products, null, 2));

    } catch (e) {
        console.error("Error:", e.message);
    }
}

run();
