
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceRoleKey);

async function fixBanners() {
    console.log("Checking banners table...");
    try {
        const { error: err1 } = await supabase.rpc('exec_sql', {
            sql_query: "ALTER TABLE banners ADD COLUMN IF NOT EXISTS bg_color TEXT DEFAULT '#F1F8F1'"
        });
        if (err1) console.log("bg_color error (maybe rpc missing):", err1.message);
        else console.log("bg_color column ensured.");

        const { error: err2 } = await supabase.rpc('exec_sql', {
            sql_query: "ALTER TABLE banners ADD COLUMN IF NOT EXISTS subtitle TEXT"
        });
        if (err2) console.log("subtitle error (maybe rpc missing):", err2.message);
        else console.log("subtitle column ensured.");
        
        // If RPC fails, try directly inserting (though usually only works for DML)
        // But we need to ensure these columns exist for the Admin UI to work.
    } catch (e) {
        console.error("Fatal:", e);
    }
}

fixBanners();
