const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://dxqcruvarqgnscenixzf.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY'
);

async function checkUserHistory(phone) {
    const digits = phone.replace(/\D/g, '');
    const short = digits.length > 10 ? digits.slice(-10) : digits;
    
    console.log(`Checking history for short phone: ${short}`);
    
    const { data, error } = await supabase
        .from('orders')
        .select('*')
        .or(`delivery_phone.ilike.%${short}%,customer_id.ilike.%${short}%`)
        .order('created_at', { ascending: false });

    if (error) {
        console.error('Error fetching orders:', error);
        return;
    }

    console.log(`Found ${data.length} orders.`);
    data.forEach(o => {
        console.log(`- [${o.created_at}] ID: ${o.id} | Status: ${o.order_status} | Payment: ${o.payment_status} | Total: ${o.total_amount} | Phone: ${o.delivery_phone}`);
    });
}

checkUserHistory('8897868951');
