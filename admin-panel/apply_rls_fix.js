import { createClient } from '@supabase/supabase-js'
import fs from 'fs'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function applyFix() {
    console.log("Reading FIX_RLS_PERMISSIONS.sql...");
    const sql = fs.readFileSync('FIX_RLS_PERMISSIONS.sql', 'utf8');

    console.log("Applying RLS fixes via exec_sql RPC...");
    const { data, error } = await supabase.rpc('exec_sql', { sql });

    if (error) {
        console.error("SQL EXECUTION FAILED:", error.message);
        // Fallback: try individual statements if exec_sql fails
        console.log("Attempting fallback execution...");
        // Split by semicolon (naive)
        const statements = sql.split(';').filter(s => s.trim().length > 0);
        for (const statement of statements) {
            const { error: stmtError } = await supabase.rpc('exec_sql', { sql: statement + ';' });
            if (stmtError) console.error(`Error in statement: ${statement.substring(0, 50)}...`, stmtError.message);
        }
    } else {
        console.log("SQL EXECUTION SUCCESSFUL:", data);
    }
}

applyFix();
