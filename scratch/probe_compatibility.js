const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function callRpc(name, params) {
    const data = JSON.stringify(params);
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'dxqcruvarqgnscenixzf.supabase.co',
            port: 443,
            path: `/rest/v1/rpc/${name}`,
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
                resolve({ status: res.statusCode, body: body });
            });
        });
        req.on('error', reject);
        req.write(data);
        req.end();
    });
}

async function run() {
    const lat = 17.3850;
    const lng = 78.4867;

    console.log(">>> Testing get_popular_near_you_v2 with 3 params (lat, lng, radius:double)...");
    const res1 = await callRpc('get_popular_near_you_v2', { p_lat: lat, p_lng: lng, p_radius: 5000 });
    console.log("Status 1:", res1.status, res1.body);

    console.log("\n>>> Testing get_popular_near_you_v2 with 3 params (lat, lng, p_category_id:text)...");
    const res2 = await callRpc('get_popular_near_you_v2', { p_lat: lat, p_lng: lng, p_category_id: "test" });
    console.log("Status 2:", res2.status, res2.body);

    console.log("\n>>> Testing get_popular_near_you_v2 with 2 params...");
    const res3 = await callRpc('get_popular_near_you_v2', { p_lat: lat, p_lng: lng });
    console.log("Status 3:", res3.status, res3.body);
}

run();
