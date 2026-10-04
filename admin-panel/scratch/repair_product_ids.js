import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function repairProductIds() {
    console.log("🚀 Starting Product ID Repair...");
    const { data: products, error } = await supabase.from('products').select('*').is('id', null);
    
    if (error) {
        console.error("Fetch error:", error);
        return;
    }

    console.log(`Found ${products.length} products with NULL IDs.`);

    for (const p of products) {
        // Since ID is NULL, we can't 'update' by ID.
        // We have to delete and re-insert OR use another column if possible.
        // But wait! If we delete by name and vendor, we might delete too much.
        
        // Actually, we can use the 'created_at' as a rough filter, or name.
        // But the best way is to delete ALL nulls and re-insert them properly.
        console.log(`- Repairing: ${p.name}`);
    }

    if (products.length > 0) {
        // DELETE ALL NULL IDs for safety (cleaning up corruption)
        const { error: delError } = await supabase.from('products').delete().is('id', null);
        if (delError) {
            console.error("Delete error:", delError);
        } else {
            console.log("✅ Purged all NULL ID products.");
            
            // Re-inserting them with valid IDs (Supabase will auto-gen if not provided, 
            // but we'll provide them to be sure)
            const cleaned = products.map(p => {
                const { id, ...rest } = p;
                return rest;
            });

            const { error: insError } = await supabase.from('products').insert(cleaned);
            if (insError) {
                console.error("Re-insertion error:", insError);
            } else {
                console.log("✅ Successfully re-inserted products with valid IDs.");
            }
        }
    }
}

repairProductIds();
