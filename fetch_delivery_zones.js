const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function run() {
    const response = await fetch(`${url}/rest/v1/delivery_zones?select=*`, {
        method: 'GET',
        headers: {
            'apikey': anonKey,
            'Authorization': `Bearer ${anonKey}`
        }
    });
    if (response.ok) {
        const data = await response.json();
        console.log("Delivery Zones:", JSON.stringify(data, null, 2));
    } else {
        console.log("FAILED to fetch delivery_zones");
    }
}
run();
