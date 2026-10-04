
const https = require('https');

const apiKey = 'AIzaSyAqpif-LqTA5KczhJtkKzG8RXK8lrhMyJQ';
const lat = 17.3850;
const lng = 78.4867;
const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}`;

https.get(url, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
        const json = JSON.parse(data);
        console.log(JSON.stringify(json, null, 2));
    });
}).on('error', (err) => {
    console.error('Error: ' + err.message);
});
