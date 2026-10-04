import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceKey);

async function fixVendors() {
    console.log("Fixing vendors to be OPEN and ONLINE...");
    
    const { data, error } = await supabase
        .from('vendors')
        .update({ is_open: true, status: 'ONLINE' })
        .eq('is_active', true);

    if (error) {
        console.error("Error updating vendors:", error);
    } else {
        console.log("Vendors updated successfully!");
    }
}

fixVendors();
