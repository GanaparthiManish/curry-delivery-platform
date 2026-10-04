const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
  console.log("Simulating get_popular_near_you_v2 RPC...");
  const { data, error } = await supabase.rpc('get_popular_near_you_v2', {
    p_category_id: null,
    p_lat: 17.4483,
    p_lng: 78.3488
  });

  console.log("Data:", data);
  console.log("Error:", error);
}

run();
