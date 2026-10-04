const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODAyNDY3OSwiZXhwIjoyMDgzNjAwNjc5fQ.qIQG3723MjMu9YMLoRQXGepqCzllJWHFiLLcOKV6O3s';

const supabase = createClient(supabaseUrl, serviceRoleKey);

async function run() {
  const sql = fs.readFileSync('../UPI_STABILITY_AUDIT_V1.sql', 'utf8');
  console.log("Applying UPI Stability Audit SQL...");
  
  const { data, error } = await supabase.rpc('exec_sql', {
      query: sql
  });
  
  if (error) {
      console.error("Failed to apply SQL:", error.message);
  } else {
      console.log("SQL Applied Successfully!");
  }
}

run();
