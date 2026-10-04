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
        const vendors = await get('vendors?select=id,name,status,latitude,longitude&limit=3');
        console.log("Top 3 Vendors:", JSON.stringify(vendors, null, 2));

        const lat1 = 17.3850;
        const lng1 = 78.4867;

        vendors.forEach(v => {
            const lat2 = v.latitude;
            const lng2 = v.longitude;
            if (lat2 && lng2) {
                const R = 6371;
                const dLat = (lat2 - lat1) * Math.PI / 180;
                const dLng = (lng2 - lng1) * Math.PI / 180;
                const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                    Math.sin(dLng / 2) * Math.sin(dLng / 2);
                const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
                const d = R * c;
                console.log(`Vendor: ${v.name}, Dist to Hyderabad Center: ${d.toFixed(2)} km, Status: ${v.status}`);
            }
        });

    } catch (e) {
        console.error("Error:", e.message);
    }
}

run();
