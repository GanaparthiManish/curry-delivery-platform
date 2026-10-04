const { createClient } = require('@supabase/supabase-js');
const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';
const supabase = createClient(url, serviceKey);

async function checkVendors() {
    const { data, error } = await supabase.from('vendors').select('id, name, delivery_radius_km, latitude, longitude');
    if (error) console.error(error);
    else {
        data.forEach(v => {
            console.log(`Vendor: ${v.name} (${v.id}), Radius: ${v.delivery_radius_km}, Coords: ${v.latitude}, ${v.longitude}`);
        });
    }
}
checkVendors();
