async function findSqlRpc() {
    const url = 'https://dxqcruvarqgnscenixzf.supabase.co/rest/v1/';
    const apikey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';
    
    const res = await fetch(url, {
        headers: { 'apikey': apikey }
    });
    const schema = await res.json();
    const paths = Object.keys(schema.paths);
    const rpcs = paths.filter(p => p.includes('sql') || p.includes('exec') || p.includes('run'));
    console.log("Candidate RPCS:", rpcs);
}

findSqlRpc();
