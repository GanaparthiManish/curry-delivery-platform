const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('schema_summary.json', 'utf8'));
const rpcs = Object.keys(schema.paths).filter(p => p.startsWith('/rpc/'));
console.log("exec/sql/run/query rpcs:", rpcs.filter(p => p.includes('sql') || p.includes('exec') || p.includes('run') || p.includes('query')));
