const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('https://dxqcruvarqnscenixfzf.supabase.co', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s');

async function inspect() {
    console.log("--- VENDORS COLS ---");
    const { data: cols } = await supabase.rpc('inspect_columns', { table_name: 'vendors' });
    console.log(cols);

    console.log("--- ORDERS COLS ---");
    const { data: ocols } = await supabase.rpc('inspect_columns', { table_name: 'orders' });
    console.log(ocols);

    console.log("--- MASTER ORDERS COLS ---");
    const { data: mcols } = await supabase.rpc('inspect_columns', { table_name: 'master_orders' });
    console.log(mcols);
}

inspect();
