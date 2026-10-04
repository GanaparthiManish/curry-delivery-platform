const https = require('https');

const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function list() {
    const options = {
        hostname: 'dxqcruvarqgnscenixzf.supabase.co',
        port: 443,
        path: '/rest/v1/rpc/st_astext?limit=1', // Just to check connectivity
        method: 'POST',
        headers: {
            'apikey': serviceKey,
            'Authorization': 'Bearer ' + serviceKey,
            'Content-Type': 'application/json'
        }
    };

    // Actually, let's query pg_proc via REST
    const queryOptions = {
        hostname: 'dxqcruvarqgnscenixzf.supabase.co',
        port: 443,
        path: '/rest/v1/pg_proc?select=proname&proname=ilike.*sql*',
        method: 'GET',
        headers: {
            'apikey': serviceKey,
            'Authorization': 'Bearer ' + serviceKey
        }
    };

    const req = https.request(queryOptions, (res) => {
        let body = '';
        res.on('data', (d) => body += d);
        res.on('end', () => {
            console.log("SQL RPCS:", body);
        });
    });
    req.end();
}

list();
