
const { createClient } = require('@supabase/supabase-js');

const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

const supabase = createClient(url, key);

async function debug() {
    console.log("Checking Online Vendors...");
    const { data: vendors, error: vErr } = await supabase
        .from('vendors')
        .select('id, name, status, latitude, longitude, address')
        .eq('status', 'ONLINE');

    if (vErr) {
        console.error("Vendor Error:", vErr);
        return;
    }

    console.log(`Found ${vendors.length} ONLINE vendors:`);
    vendors.forEach(v => {
        console.log(`- ${v.name} (${v.id}): [${v.latitude}, ${v.longitude}] at ${v.address}`);
    });

    if (vendors.length > 0) {
        const v = vendors[0];
        console.log(`\nTesting get_popular_near_you_v2 near ${v.name}...`);
        const { data: items, error: iErr } = await supabase.rpc('get_popular_near_you_v2', {
            p_lat: v.latitude,
            p_lng: v.longitude
        });

        if (iErr) {
            console.error("RPC Error:", iErr);
        } else {
            console.log(`Found ${items ? items.length : 0} items nearby.`);
            if (items && items.length > 0) {
                console.log("First item sample:", JSON.stringify(items[0], null, 2));
            }
        }
    } else {
        console.log("No online vendors found to test with.");
    }

    console.log("\nChecking Live Tracking for active orders...");
    const { data: tracking, error: tErr } = await supabase
        .from('order_live_tracking')
        .select('*')
        .order('last_updated', { ascending: false })
        .limit(5);

    if (tErr) {
        console.error("Tracking Error:", tErr);
    } else {
        console.log(`Found ${tracking.length} tracking records:`);
        tracking.forEach(t => {
            console.log(`- Order ${t.order_id}: [${t.latitude}, ${t.longitude}] updated at ${t.last_updated}`);
        });
    }
}

debug();
