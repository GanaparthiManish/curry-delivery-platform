const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function run() {
    const response = await fetch(`${url}/rest/v1/vendors?id=eq.62cfce56-a678-4d7b-89a8-dba12591a856`, {
        method: 'PATCH',
        headers: {
            'apikey': anonKey,
            'Authorization': `Bearer ${anonKey}`,
            'Content-Type': 'application/json',
            'Prefer': 'return=minimal'
        },
        body: JSON.stringify({
            delivery_radius_km: 100
        })
    });
    if (response.ok) {
        console.log("SUCCESS! Updated via anon key.");
    } else {
        const err = await response.json();
        console.log("FAILED via anon key:", err.message);
    }
}
run();
