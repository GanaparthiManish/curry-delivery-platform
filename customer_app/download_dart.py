import urllib.request
import time
import sys

url = "https://storage.googleapis.com/flutter_infra_release/flutter/425cfb54d01a9472b3e81d9e76fd63a4a44cfbcb/dart-sdk-windows-x64.zip"
file_name = "dart-sdk.zip"

print(f"Downloading {url} to {file_name}...")

def download_with_retry():
    max_retries = 10
    for i in range(max_retries):
        try:
            urllib.request.urlretrieve(url, file_name)
            print("Download successful!")
            return True
        except Exception as e:
            print(f"Attempt {i+1} failed: {e}")
            time.sleep(2)
    return False

if download_with_retry():
    sys.exit(0)
else:
    sys.exit(1)
