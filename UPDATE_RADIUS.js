const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function updateRadius() {
    const data = JSON.stringify({
        delivery_radius_km: 15,
        radius_km: 15
    });

    const options = {
        hostname: supabaseUrl.replace('https://', ''),
        port: 443,
        path: '/rest/v1/vendors?id=not.is.null',
        method: 'PATCH',
        headers: {
            'Content-Type': 'application/json',
            'apikey': serviceKey,
            'Authorization': 'Bearer ' + serviceKey
        }
    };

    const req = https.request(options, (res) => {
        console.log('Status Code:', res.statusCode);
        let body = '';
        res.on('data', d => body += d);
        res.on('end', () => console.log('Response:', body));
    });

    req.on('error', (error) => console.error(error));
    req.write(data);
    req.end();
}

updateRadius();
