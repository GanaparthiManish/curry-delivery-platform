const { createClient } = require('@supabase/supabase-js');

const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

const supabase = createClient(url, anonKey);

async function checkData() {
  console.log("Checking Products...");
  const { data: products, error: pError } = await supabase
    .from('products')
    .select('id, name, is_active, item_type, category_id')
    .limit(10);
  
  if (pError) console.error("Products Error:", pError);
  else console.log("Recent Products:", products);

  console.log("\nChecking Vendors...");
  const { data: vendors, error: vError } = await supabase
    .from('vendors')
    .select('id, name, status, is_open, is_active, latitude, longitude')
    .limit(10);
    
  if (vError) console.error("Vendors Error:", vError);
  else console.log("Recent Vendors:", vendors);

  console.log("\nChecking Vendor Products Mapping...");
  const { data: vp, error: vpError } = await supabase
    .from('vendor_products')
    .select('id, vendor_id, product_id, is_available')
    .limit(10);
    
  if (vpError) console.error("VP Error:", vpError);
  else console.log("Recent VP Mappings:", vp);
}

checkData();
