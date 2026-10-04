import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function checkPK() {
    const { data, error } = await supabase.rpc('get_table_info', { t_name: 'products' });
    if (error) {
        console.log("RPC get_table_info failed, trying generic query...");
        // This is a common pattern to check if the table has multiple primary keys or unusual ones
        const { data: cols } = await supabase.from('products').select('*').limit(1);
        console.log("Columns:", Object.keys(cols[0]));
    } else {
        console.log("Table info:", data);
    }
}

checkPK();
