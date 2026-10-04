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
    // Hyderabad Center coords from LocationStore
    const lat = 17.3850;
    const lng = 78.4867;

    console.log(`>>> Calling get_popular_near_you_v2 at ${lat}, ${lng}...`);
    const res = await callRpc('get_popular_near_you_v2', { p_lat: lat, p_lng: lng });
    console.log("Status:", res.status);
    console.log("Body:", res.body);
}

run();
