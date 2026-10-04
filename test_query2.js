const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

async function testQuery() {
  console.log("=== Querying Products ===");
  try {
    const res = await fetch(`${url}/rest/v1/products?select=*,vendors(*)&name=ilike.*chicken*`, {
      headers: {
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
      }
    });
    const text = await res.text();
    console.log("Status:", res.status);
    console.log("Response ERROR:", text);
    
    const broadRes = await fetch(`${url}/rest/v1/products?select=*,vendors(*)&or=(name.ilike.*chicken*,description.ilike.*chicken*,category.ilike.*chicken*)`, {
      headers: {
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
      }
    });
    const broadText = await broadRes.text();
    console.log("Broad Status:", broadRes.status);
    console.log("Broad ERROR:", broadText);

  } catch (e) {
    console.error(e);
  }
}

testQuery();
