const { createClient } = require('@supabase/supabase-js');
const sb = createClient(
  'https://dxqcruvarqgnscenixzf.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'
);

async function check() {
  // Check a recent order for coordinates
  const { data: orders } = await sb.from('orders')
    .select('id, status, payment_method, delivery_lat, delivery_lng, vendor_lat, vendor_lng, rider_lat, rider_lng, vendor_id, rider_id, created_at')
    .order('created_at', { ascending: false })
    .limit(5);
  console.log('\n=== LATEST ORDERS COORDINATES ===');
  console.log(JSON.stringify(orders, null, 2));

  // Check vendors table for lat/lng columns
  const { data: vendors } = await sb.from('vendors')
    .select('id, name, lat, lng, latitude, longitude, location')
    .limit(3);
  console.log('\n=== VENDORS COORDINATES ===');
  console.log(JSON.stringify(vendors, null, 2));

  // Check delivery_riders for current_lat/lng
  const { data: riders } = await sb.from('delivery_riders')
    .select('id, name, current_lat, current_lng, lat, lng')
    .limit(3);
  console.log('\n=== RIDERS COORDINATES ===');
  console.log(JSON.stringify(riders, null, 2));
}

check().catch(console.error);
