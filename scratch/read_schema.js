const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('schema_summary.json', 'utf8'));
const ordersDef = schema.definitions ? schema.definitions.orders : schema.orders;
console.log(Object.keys(ordersDef.properties));
