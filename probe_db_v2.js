
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';
const supabase = createClient(supabaseUrl, supabaseKey);

async function probe() {
    const { data: tables, error } = await supabase.rpc('exec_sql_v1', {
        sql_query: "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
    });
    
    if (error) {
        console.error("Error:", error);
        // Fallback to direct REST probe
        const res = await fetch(`${supabaseUrl}/rest/v1/?apikey=${supabaseKey}`);
        console.log("REST Endpoints:", await res.text());
        return;
    }
    
    console.log("Tables:", tables.map(t => t.table_name).join(', '));
}

probe();
