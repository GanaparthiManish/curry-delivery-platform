import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function checkPolicies() {
    console.log("Fetching RLS policies for table 'categories'...");
    const { data, error } = await supabase.rpc('exec_sql', { 
        sql: "SELECT * FROM pg_policies WHERE tablename = 'categories';" 
    });

    if (error) {
        console.error("Error executing SQL:", error.message);
        return;
    }

    console.log("Policies found:", JSON.stringify(data, null, 2));
}

checkPolicies();
