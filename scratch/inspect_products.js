const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function inspectProducts() {
  try {
    const res = await fetch(`${url}/rest/v1/products?select=id,name,is_popular,is_active,item_type,category_id`, {
      headers: {
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
      }
    });
    const items = await res.json();
    console.log(`Total Products: ${items.length}`);
    const active = items.filter(i => i.is_active);
    console.log(`Active Products: ${active.length}`);
    const popular = items.filter(i => i.is_popular);
    console.log(`Popular Products: ${popular.length}`);
    const activePopular = active.filter(i => i.is_popular);
    console.log(`Active Popular Products: ${activePopular.length}`);
    const activeNormal = active.filter(i => !i.is_popular);
    console.log(`Active Normal Products: ${activeNormal.length}`);
    console.log("Sample Active Normal:", activeNormal.slice(0, 5));
    console.log("Sample Active Popular:", activePopular.slice(0, 5));
  } catch (e) {
    console.error(e);
  }
}

inspectProducts();
