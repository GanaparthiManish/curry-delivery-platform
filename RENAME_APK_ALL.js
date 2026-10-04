const fs = require('fs');
const path = require('path');

const srcRelease = 'customer_app/build/app/outputs/flutter-apk/app-release.apk';
const srcDebug = 'customer_app/build/app/outputs/flutter-apk/app-debug.apk';
const destRelease = 'CUSTOMER_APP_V40_STRICT_5KM_RELEASE.apk';
const destDebug = 'CUSTOMER_DEBUG_V40_STRICT_5KM.apk';

async function waitForApks() {
    console.log("Monitoring for build completion...");
    
    let releaseFound = false;
    let debugFound = false;

    while (!releaseFound || !debugFound) {
        if (!releaseFound && fs.existsSync(srcRelease)) {
            console.log("Release APK found! Copying...");
            fs.copyFileSync(srcRelease, destRelease);
            releaseFound = true;
        }
        if (!debugFound && fs.existsSync(srcDebug)) {
            console.log("Debug APK found! Copying...");
            fs.copyFileSync(srcDebug, destDebug);
            debugFound = true;
        }
        await new Promise(r => setTimeout(r, 10000));
    }
    console.log("All APKs processed successfully!");
}

waitForApks();
