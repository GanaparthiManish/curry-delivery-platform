import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co'
const serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6ImpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s'

const supabase = createClient(supabaseUrl, serviceKey)

async function listRPCs() {
    // Try to query pg_proc via a direct SQL if possible, or just list common potential ones
    const { data: procs, error: procError } = await supabase.from('pg_proc').select('proname');
    if (procError) {
        console.log("Could not query pg_proc directly. Trying generic RPC check.");
    } else {
        console.log("Procs:", procs.map(p => p.proname));
    }
}

listRPCs();
