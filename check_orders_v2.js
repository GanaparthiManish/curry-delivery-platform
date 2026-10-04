const { createClient } = require('@supabase/supabase-client');
require('dotenv').config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY);

async function checkOrders() {
    const { data, error } = await supabase
        .from('orders')
        .select('id, customer_id, status, created_at')
        .order('created_at', { ascending: false })
        .limit(5);
    
    if (error) {
        console.error('Error fetching orders:', error);
    } else {
        console.log('Latest 5 orders:', JSON.stringify(data, null, 2));
    }
}

checkOrders();
