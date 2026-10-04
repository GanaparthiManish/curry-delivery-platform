import { createClient } from '@supabase/supabase-js'
import fs from 'fs'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function runNuclearFix() {
    const sql = fs.readFileSync('scratch/nuclear_fix_rls.sql', 'utf8');
    // We try to find a working RPC to execute SQL
    const rpcs = ['exec_sql', 'execute_sql', 'sql', 'run_sql'];
    
    for (const rpc of rpcs) {
        console.log(`Trying RPC: ${rpc}...`);
        const { data, error } = await supabase.rpc(rpc, { sql });
        if (!error) {
            console.log(`✅ SUCCESS with RPC: ${rpc}`);
            return;
        }
        console.log(`❌ FAILED with RPC ${rpc}: ${error.message}`);
    }
}

runNuclearFix();
