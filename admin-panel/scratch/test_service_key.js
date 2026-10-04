import { createClient } from '@supabase/supabase-js';

const URL = 'https://dxqcruvarqgnscenixzf.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

const admin = createClient(URL, SERVICE_KEY);
const anon = createClient(URL, ANON_KEY);

async function test() {
    console.log('\n=== TESTING SERVICE KEY ===');
    const { data: cats, error: catErr } = await admin.from('categories').select('id, name').limit(5);
    if (catErr) console.error('❌ SERVICE KEY - Categories SELECT:', catErr.message);
    else console.log('✅ SERVICE KEY - Categories SELECT OK, count:', cats.length);

    const { data: vends, error: vendErr } = await admin.from('vendors').select('id, name').limit(5);
    if (vendErr) console.error('❌ SERVICE KEY - Vendors SELECT:', vendErr.message);
    else console.log('✅ SERVICE KEY - Vendors SELECT OK, count:', vends.length);

    // Test INSERT on categories
    const { data: ins, error: insErr } = await admin.from('categories').insert([{
        name: '__test_admin_bypass__', is_active: true, priority: 0
    }]).select();
    if (insErr) console.error('❌ SERVICE KEY - Categories INSERT FAILED:', insErr.message, insErr.code);
    else {
        console.log('✅ SERVICE KEY - Categories INSERT OK:', ins[0].id);
        // Clean up
        await admin.from('categories').delete().eq('id', ins[0].id);
        console.log('🗑️  Test record cleaned up');
    }

    console.log('\n=== TESTING ANON KEY ===');
    const { data: aCats, error: aCatErr } = await anon.from('categories').select('id, name').limit(5);
    if (aCatErr) console.error('❌ ANON KEY - Categories SELECT:', aCatErr.message);
    else console.log('✅ ANON KEY - Categories SELECT OK, count:', aCats.length);
}

test().catch(console.error);
