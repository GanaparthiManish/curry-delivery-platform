const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('schema_summary.json', 'utf8'));
const rpcs = Object.keys(schema.paths).filter(p => p.startsWith('/rpc/'));
console.log("POPULAR:", rpcs.filter(p => p.includes('popular')));
