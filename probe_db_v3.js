
const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function probe() {
    try {
        const res = await fetch(`${supabaseUrl}/rest/v1/`, {
            headers: { 'apikey': supabaseKey }
        });
        const data = await res.json();
        console.log("Available Tables:", Object.keys(data.definitions || {}).join(', '));
    } catch (e) {
        console.error("Error:", e);
    }
}

probe();
