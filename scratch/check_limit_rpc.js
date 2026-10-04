const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function run() {
  const res = await fetch(`${url}/rest/v1/rpc/get_popular_near_you_v2`, {
    method: 'POST',
    headers: {
      'apikey': anonKey,
      'Content-Type': 'application/json',
      'Range-Unit': 'items',
      'Range': '0-199'
    },
    body: JSON.stringify({
      p_category_id: null,
      p_lat: 17.4483,
      p_lng: 78.3488
    })
  });
  const data = await res.json();
  console.log("Returned size:", data.length);
}
run();
