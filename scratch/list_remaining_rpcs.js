const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('schema_summary.json', 'utf8'));
const rpcs = Object.keys(schema.paths).filter(p => p.startsWith('/rpc/'));
const customRpcs = rpcs.filter(p => {
    const name = p.replace('/rpc/', '');
    return !name.startsWith('st_') && !name.startsWith('_st_') && !name.startsWith('geometry_') && !name.startsWith('postgis_') && !name.startsWith('_postgis_');
});
console.log(customRpcs);
