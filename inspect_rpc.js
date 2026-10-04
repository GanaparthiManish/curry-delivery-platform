const { createClient } = require('./admin-panel/node_modules/@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function run() {
  console.log("Fetching function definition from pg_proc...");
  const { data, error } = await supabase
    .from('pg_proc')
    .select('proname, prosrc')
    .eq('proname', 'get_popular_near_you_v2');

  if (error) {
    // Try via RPC or direct REST endpoint
    console.error("Direct pg_proc query failed:", error);
    // Let's try executing SQL to query it if possible, but since we don't have exec_sql we can't.
    // Wait, let's see if we can query pg_catalog.pg_proc via standard select.
    // If not, we can query public tables or try fetching it.
  } else {
    console.log("Function Source Code:", data[0]?.prosrc);
  }
}

run();
