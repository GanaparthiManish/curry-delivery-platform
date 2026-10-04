const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function run() {
    const response = await fetch(`${url}/rest/v1/vendors?select=id,name,delivery_radius_km`, {
        method: 'GET',
        headers: {
            'apikey': anonKey,
            'Authorization': `Bearer ${anonKey}`
        }
    });
    const data = await response.json();
    console.log(JSON.stringify(data, null, 2));
}
run();
