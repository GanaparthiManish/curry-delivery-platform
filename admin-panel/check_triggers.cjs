const { createClient } = require('@supabase/supabase-js');
const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';
const supabase = createClient(url, serviceKey);

async function run() {
  const { data, error } = await supabase.rpc('exec_sql', {
    sql: `SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'orders'::regclass;`
  });
  if (error) {
    console.error("RPC ERROR:", error);
  } else {
    console.log("Triggers:", JSON.stringify(data, null, 2));
  }
}
run();
