const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function fixVendors() {
    console.log("Fixing vendors to be OPEN and ONLINE...");
    
    const data = JSON.stringify({
        is_open: true,
        status: 'ONLINE'
    });

    const options = {
        hostname: supabaseUrl.replace('https://', ''),
        port: 443,
        path: '/rest/v1/vendors?is_active=eq.true',
        method: 'PATCH',
        headers: {
            'Content-Type': 'application/json',
            'apikey': serviceKey,
            'Authorization': 'Bearer ' + serviceKey,
            'Content-Length': data.length
        }
    };

    const req = https.request(options, (res) => {
        let body = '';
        res.on('data', (d) => body += d);
        res.on('end', () => {
            if (res.statusCode >= 200 && res.statusCode < 300) {
                console.log("Vendors updated successfully!");
            } else {
                console.error("Error updating vendors:", res.statusCode, body);
            }
        });
    });

    req.on('error', (e) => console.error(e));
    req.write(data);
    req.end();
}

fixVendors();
