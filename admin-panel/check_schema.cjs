const { createClient } = require('@supabase/supabase-js');
const sb = createClient(
  'https://dxqcruvarqgnscenixzf.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'
);

async function check() {
  // Get delivery_riders columns
  const { data: riders } = await sb.from('delivery_riders').select('*').limit(1);
  console.log('\n=== DELIVERY_RIDERS COLUMNS ===');
  if (riders && riders.length > 0) console.log(Object.keys(riders[0]));
  else console.log('No riders in DB, columns:', riders);

  // Get vendors columns
  const { data: vendors } = await sb.from('vendors').select('*').limit(1);
  console.log('\n=== VENDORS COLUMNS ===');
  if (vendors && vendors.length > 0) console.log(Object.keys(vendors[0]));

  // Get orders columns
  const { data: orders } = await sb.from('orders').select('*').limit(1);
  console.log('\n=== ORDERS COLUMNS ===');
  if (orders && orders.length > 0) console.log(Object.keys(orders[0]));
}

check().catch(console.error);
