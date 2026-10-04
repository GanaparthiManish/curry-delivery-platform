const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('https://dxqcruvarqgnscenixzf.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s');

async function inspect() {
    const { data, error } = await supabase.rpc('exec_sql', { 
        sql: "SELECT routine_definition FROM information_schema.routines WHERE routine_name = 'place_order_stabilized_v5'" 
    });
    if (error) {
        console.error("RPC ERROR:", error);
        return;
    }
    console.log(data);
}

inspect();
