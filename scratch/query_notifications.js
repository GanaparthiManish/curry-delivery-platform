const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

async function run() {
    try {
        console.log("Querying latest 10 notifications...");
        const res = await fetch(`${supabaseUrl}/rest/v1/notifications?order=created_at.desc&limit=10`, {
            headers: {
                'apikey': serviceKey,
                'Authorization': `Bearer ${serviceKey}`
            }
        });
        const notifications = await res.json();
        console.log("Latest Notifications:", JSON.stringify(notifications, null, 2));
    } catch (e) {
        console.error(e);
    }
}

run();
