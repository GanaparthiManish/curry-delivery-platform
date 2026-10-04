import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function findSqlRpc() {
    const { data, error } = await supabase.from('pg_proc').select('proname').ilike('proname', '%sql%');
    if (error) {
        console.log("Error querying pg_proc:", error.message);
        // Try information_schema
        const { data: data2, error: error2 } = await supabase.rpc('get_functions'); // Some projects have this
        console.log("Functions from RPC:", data2 || error2?.message);
    } else {
        console.log("SQL Functions found:", data.map(p => p.proname).join(", "));
    }
}

findSqlRpc();
