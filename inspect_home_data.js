const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
  console.log("Testing direct join via products.vendor_id...");
  const { data, error } = await supabase
    .from('products')
    .select('*, vendors(*)')
    .limit(1);

  if (error) {
    console.error("Direct Join Error:", error);
  } else {
    console.log("Direct Join Success:", JSON.stringify(data[0], null, 2));
  }
}

run();
