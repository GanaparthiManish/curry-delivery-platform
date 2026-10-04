const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    'https://dxqcruvarqgnscenixzf.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'
);

async function check() {
  const { data, error } = await supabase.from('orders').select('*').ilike('id', 'da80b10e%');
  console.log("Order Data:", data, "Error:", error);
  if (data && data.length > 0) {
      const { data: vData } = await supabase.from('vendors').select('*').eq('id', data[0].vendor_id);
      console.log("Vendor Data:", vData);
  } else {
      const { data: vData2 } = await supabase.from('vendors').select('*').ilike('name', '%katyayani%');
      console.log("Katyayani Vendor Data:", vData2);
  }
}
check();
