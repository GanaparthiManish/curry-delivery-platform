import { createClient } from '@supabase/supabase-js';

const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

const supabase = createClient(url, anonKey);

async function main() {
  const { data: vendors, error: vErr } = await supabase.from('vendors').select('id, name, status, is_active, latitude, longitude');
  
  const statuses = new Set(vendors.map(v => v.status));
  console.log("Unique Vendor Statuses:", Array.from(statuses));
}

main();
