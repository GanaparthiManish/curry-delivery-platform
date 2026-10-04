const https = require('https');

const url = 'https://dxqcruvarqgnscenixzf.supabase.co/rest/v1/rpc/get_rpc_details';
const apikey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

const data = JSON.stringify({ rpc_name: 'confirm_upi_payment_v2' });

const options = {
    method: 'POST',
    headers: {
        'apikey': apikey,
        'Authorization': `Bearer ${apikey}`,
        'Content-Type': 'application/json'
    }
};

const req = https.request(url, options, (res) => {
    let responseData = '';
    res.on('data', (chunk) => { responseData += chunk; });
    res.on('end', () => {
        console.log(responseData);
    });
});

req.on('error', (err) => {
    console.error(err);
});

req.write(data);
req.end();
