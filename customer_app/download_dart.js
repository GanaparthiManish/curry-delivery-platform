const https = require('https');
const fs = require('fs');
const path = require('path');

const url = "https://storage.googleapis.com/flutter_infra_release/flutter/425cfb54d01a9472b3e81d9e76fd63a4a44cfbcb/dart-sdk-windows-x64.zip";
const filePath = path.join(__dirname, 'dart-sdk.zip');

function downloadFile(url, dest) {
    return new Promise((resolve, reject) => {
        let stats;
        try {
            stats = fs.statSync(dest);
        } catch (e) {
            stats = { size: 0 };
        }
        
        const options = {};
        if (stats.size > 0) {
            options.headers = { 'Range': `bytes=${stats.size}-` };
            console.log(`Resuming download from ${stats.size} bytes...`);
        } else {
            console.log(`Starting fresh download...`);
        }

        const req = https.get(url, options, (res) => {
            if (res.statusCode === 206 || res.statusCode === 200) {
                const file = fs.createWriteStream(dest, { flags: stats.size > 0 ? 'a' : 'w' });
                res.pipe(file);
                
                file.on('finish', () => {
                    file.close();
                    console.log('Download chunk complete.');
                    resolve(res.headers['content-length']);
                });
            } else if (res.statusCode === 416) {
                console.log('File fully downloaded (416 range error).');
                resolve(0);
            } else {
                reject(`Server responded with ${res.statusCode}: ${res.statusMessage}`);
            }
        });

        req.on('error', (err) => {
            console.error('Download interrupted:', err.message);
            reject(err);
        });
    });
}

async function start() {
    let retries = 0;
    while (retries < 20) {
        try {
            const addedBytes = await downloadFile(url, filePath);
            if (addedBytes == 0 || addedBytes === undefined || addedBytes < 100) {
                console.log("Download seems complete. Exiting loop.");
                break;
            }
        } catch (e) {
            console.log(`Retrying after failure (${retries+1}/20)...`);
            retries++;
            await new Promise(r => setTimeout(r, 2000));
        }
    }
}

start();
