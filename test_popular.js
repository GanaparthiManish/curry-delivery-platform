async function testRpc() {
    const url = 'https://dxqcruvarqgnscenixzf.supabase.co/rest/v1/rpc/get_popular_near_you_v2';
    const apikey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';
    
    try {
        const res = await fetch(url, {
            method: 'POST',
            headers: {
                'apikey': apikey,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                p_lat: 17.3850,
                p_lng: 78.4867,
                p_radius_km: 15
            })
        });
        
        const text = await res.text();
        console.log("Status:", res.status);
        console.log("Response:", text);
    } catch (e) {
        console.error("Fetch error:", e);
    }
}

testRpc();
