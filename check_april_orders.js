
const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function check() {
    const phones = ['8309129294', '918309129294', '+918309129294'];
    for (const p of phones) {
        const res = await fetch(`${supabaseUrl}/rest/v1/orders?delivery_phone=ilike.*${p}*&select=id,customer_id,delivery_phone,created_at,status`, {
            headers: { 'apikey': supabaseKey }
        });
        const data = await res.json();
        console.log(`Orders for ${p}:`, data.length);
        if (data.length > 0) {
            console.log("Sample IDs used:", [...new Set(data.map(o => o.customer_id))]);
        }
    }
}

check();
