const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
  console.log("Updating all vendors to 'Active' (camel case)...");
  const { data, error } = await supabase
    .from('vendors')
    .update({ status: 'Active', is_open: true, is_active: true })
    .neq('id', '00000000-0000-0000-0000-000000000000');

  if (error) {
    console.error("Error:", error);
    return;
  }

  console.log("Success! Verifying...");
  const { data: vendors, error: fetchError } = await supabase
    .from('vendors')
    .select('id, name, status, is_open');

  console.log(`Verified ${vendors.length} vendors status:`);
  for (const v of vendors) {
    console.log(`Vendor: ${v.name} -> status: ${v.status}, is_open: ${v.is_open}`);
  }
}

run();
