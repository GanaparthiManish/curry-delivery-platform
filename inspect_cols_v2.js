
const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const tableName = process.argv[2] || 'delivery_riders';

async function getColumnDetails() {
    try {
        const response = await fetch(`${supabaseUrl}/rest/v1/${tableName}?select=*&limit=1`, {
            method: 'GET',
            headers: {
                'apikey': supabaseKey,
                'Authorization': `Bearer ${supabaseKey}`
            }
        });

        const data = await response.json();
        if (data && data.length > 0) {
            console.log(`Column names in ${tableName} table:`, Object.keys(data[0] || {}).join(', '));
            console.log("Sample row:", JSON.stringify(data[0], null, 2));
        } else {
            console.log(`No data found in ${tableName} table.`);
        }
    } catch (e) {
        console.error(e);
    }
}

getColumnDetails();
