const fs = require('fs');
const path = require('path');

const src = 'customer_app/build/app/outputs/flutter-apk/app-release.apk';
const dest = 'CUSTOMER_APP_V40_STRICT_5KM.apk';

async function waitForApk() {
    console.log(`Waiting for APK: ${src}...`);
    while (!fs.existsSync(src)) {
        await new Promise(r => setTimeout(r, 5000));
    }
    console.log("APK found! Renaming...");
    fs.copyFileSync(src, dest);
    console.log(`Success! APK updated at: ${dest}`);
}

waitForApk();
