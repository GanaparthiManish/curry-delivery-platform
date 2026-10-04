const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function testQuery() {
  console.log("=== Checking Constraints and Check constraints ===");
  try {
    const res = await fetch(`${url}/rest/v1/rpc/exec_sql`, {
      method: 'POST',
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        sql: `SELECT pg_get_constraintdef(c.oid) AS constraint_def FROM pg_constraint c JOIN pg_class t ON c.conrelid = t.oid WHERE t.relname = 'orders' AND c.contype = 'c';`
      })
    });
    const text = await res.text();
    console.log("Constraints Status:", res.status);
    console.log("Constraints Response:", text);
    
    // Check triggers on orders table
    const res2 = await fetch(`${url}/rest/v1/rpc/exec_sql`, {
      method: 'POST',
      headers: {
        'apikey': serviceKey,
        'Authorization': `Bearer ${serviceKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        sql: `SELECT trigger_name, action_statement FROM information_schema.triggers WHERE event_object_table = 'orders';`
      })
    });
    const text2 = await res2.text();
    console.log("Triggers Status:", res2.status);
    console.log("Triggers Response:", text2);

  } catch (e) {
    console.error(e);
  }
}

testQuery();
