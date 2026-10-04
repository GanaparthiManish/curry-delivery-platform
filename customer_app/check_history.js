const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://dxqcruvarqgnscenixzf.supabase.co',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY'
);

async function check() {
    const { data, error } = await supabase
        .from('orders')
        .select('id, created_at, order_status, total_amount, delivery_phone')
        .or('delivery_phone.eq.8897868951,delivery_phone.eq.+918897868951,delivery_phone.eq.918897868951')
        .order('created_at', { ascending: false });

    if (error) {
        console.error(error);
        return;
    }

    console.log(`Found ${data.length} orders.`);
    console.log(JSON.stringify(data, null, 2));
}

check();
