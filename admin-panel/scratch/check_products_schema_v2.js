import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
// Corrected key with 'IkpXVC'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function checkProductsSchema() {
    const { data, error } = await supabase.from('products').select('*').limit(1);
    if (error) {
        console.error("ERROR Fetching Product:", error.message);
    } else if (data && data.length > 0) {
        console.log("COLUMNS:", Object.keys(data[0]).join(", "));
    } else {
        console.log("No data in products table to infer schema.");
    }
}

checkProductsSchema();
