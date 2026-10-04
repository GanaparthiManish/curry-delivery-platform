const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    'https://dxqcruvarqgnscenixzf.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczODIxNjE4OSwiZXhwIjoyMDUzNzkyMTg5fQ.IkpXVC73vjGvVIm3v-ImpXVC5Zz6yTfX-zQp-zQpXVC'
);

async function listPolicies() {
    console.log("Checking Orders Table Status...");
    
    // We can't directly list policies via JS client, but we can try to update an order with service role.
    // If it works with service role but fails for user, it's 100% RLS.
    
    const { data, error } = await supabase
        .from('orders')
        .select('id, customer_id, status')
        .limit(1);
        
    if (error) {
        console.error("Fetch Error:", error);
    } else {
        console.log("Latest Order Snippet:", data);
    }
}

listPolicies();
