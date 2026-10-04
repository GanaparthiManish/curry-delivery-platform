const https = require('https');

const apiKey = "wOXX0s2KXXoIteKkgLn00vqrjejVVLX31b9k9MB2Hk8CkWIo3PnxWXN2E35v";
const senderId = "UNIV";
const messageId = "213446";
const entityId = "1101722820000093477";
const otp = "123456";
const phone = "919999999999"; // Test number

const url = `https://www.fast2sms.com/dev/bulkV2?authorization=${apiKey}&route=dlt&sender_id=${senderId}&message_id=${messageId}&variables_values=${otp}&numbers=${phone}&entity_id=${entityId}`;

console.log("Testing Fast2SMS URL:", url.replace(apiKey, "HIDDEN"));

https.get(url, (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
        console.log("Response Status:", res.statusCode);
        console.log("Response Body:", data);
    });
}).on("error", (err) => {
    console.log("Error:", err.message);
});
