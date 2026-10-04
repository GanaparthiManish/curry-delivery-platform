const url = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const rpcNames = ['exec_sql', 'run_sql', 'execute_sql', 'sql', 'query', 'admin_query'];
const paramNames = ['sql', 'query', 'p_sql', 'p_query', 'sql_query'];

async function probe() {
    for (const rpc of rpcNames) {
        for (const param of paramNames) {
            try {
                const response = await fetch(`${url}/rest/v1/rpc/${rpc}`, {
                    method: 'POST',
                    headers: {
                        'apikey': serviceKey,
                        'Authorization': `Bearer ${serviceKey}`,
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ [param]: 'SELECT 1' })
                });
                if (response.ok) {
                    console.log(`FOUND WORKING RPC: ${rpc} with param: ${param}`);
                    return;
                } else {
                    const err = await response.json();
                    if (err.code !== 'PGRST202') { // PGRST202 is "function not found"
                         console.log(`RPC ${rpc} found but failed with error:`, err.message);
                         if (err.message.includes('parameter') || err.message.includes('missing')) {
                             // Param might be wrong, continue probing params
                         } else {
                             // Function exists!
                             console.log(`FUNCTION ${rpc} EXISTS!`);
                             return;
                         }
                    }
                }
            } catch (e) {
                // Ignore
            }
        }
    }
    console.log("No working SQL RPC found.");
}
probe();
