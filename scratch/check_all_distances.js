const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function run() {
  const lat = 17.4483;
  const lng = 78.3488;
  const res = await fetch(`${url}/rest/v1/rpc/get_nearby_vendors_v24`, {
    method: 'POST',
    headers: {
      'apikey': anonKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ p_lat: lat, p_lng: lng })
  });
  const data = await res.json();
  console.log("All returned vendors properties:");
  data.forEach((v, i) => {
    console.log(`${i}: Name: ${v.name}, Lat: ${v.latitude}, Lng: ${v.longitude}, dist: ${v.dist}, distance: ${v.distance}, distance_km: ${v.distance_km}`);
  });
}
run();
