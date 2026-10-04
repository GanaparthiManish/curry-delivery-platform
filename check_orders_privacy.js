const { createClient } = require('@supabase/supabase-client');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';
const supabase = createClient(supabaseUrl, supabaseKey);

async function checkRLS() {
    console.log("Checking RLS and Policies for 'orders' table...");
    
    const { data, error } = await supabase.rpc('run_sql_native', {
        sql_query: `
            SELECT 
                schemaname, 
                tablename, 
                policyname, 
                permissive, 
                roles, 
                cmd, 
                qual, 
                with_check 
            FROM pg_policies 
            WHERE tablename = 'orders';
        `
    });

    if (error) {
        console.error("Error fetching policies:", error);
        return;
    }

    console.log("Current Policies on 'orders':");
    console.table(data);

    const { data: rlsStatus, error: rlsError } = await supabase.rpc('run_sql_native', {
        sql_query: `
            SELECT relname, relrowsecurity 
            FROM pg_class 
            JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace 
            WHERE relname = 'orders' AND nspname = 'public';
        `
    });

    if (rlsError) {
        console.error("Error checking RLS status:", rlsError);
    } else {
        console.log("RLS Status (t = enabled):", rlsStatus);
    }
}

checkRLS();
