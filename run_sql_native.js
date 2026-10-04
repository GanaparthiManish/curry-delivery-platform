const https = require('https');
const fs = require('fs');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const filePath = process.argv[2];
if (!filePath) {
    console.error("Usage: node run_sql_native.js <file.sql>");
    process.exit(1);
}

const sql = fs.readFileSync(filePath, 'utf8');
const data = JSON.stringify({ sql });

const options = {
    hostname: supabaseUrl.replace('https://', ''),
    port: 443,
    path: '/rest/v1/rpc/exec_sql',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'apikey': serviceKey,
        'Authorization': 'Bearer ' + serviceKey
    }
};

const req = https.request(options, (res) => {
    let body = '';
    console.log(`Status: ${res.statusCode}`);
    res.on('data', d => body += d);
    res.on('end', () => {
        console.log(`Body: ${body}`);
        if (res.statusCode >= 400) {
            console.log("Retrying with p_query...");
            const data2 = JSON.stringify({ p_query: sql });
            const req2 = https.request({...options, path: '/rest/v1/rpc/exec_sql'}, (res2) => {
                let body2 = '';
                 res2.on('data', d => body2 += d);
                 res2.on('end', () => {
                     console.log(`Status P_QUERY: ${res2.statusCode}`);
                     console.log(`Body P_QUERY: ${body2}`);
                 });
            });
            req2.write(data2);
            req2.end();
        }
    });
});

req.on('error', (e) => {
    console.error(`Error: ${e.message}`);
});

req.write(data);
req.end();
