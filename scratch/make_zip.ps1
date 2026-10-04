$root = "c:\Users\ganap\.gemini\antigravity\scratch\curry-delivery-platform"
$dest = "$root\handover_pkg"
$zipFile = "$root\UNIVFOODS_HANDOVER.zip"

# ─── Wipe old temp using Robocopy mirror trick (handles long paths) ───────────
function Wipe-Dir($path) {
    if (Test-Path $path) {
        $empty = "$root\_wipe_"
        New-Item -ItemType Directory -Path $empty -Force | Out-Null
        robocopy $empty $path /MIR /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
        Remove-Item $path -Force -ErrorAction SilentlyContinue
        Remove-Item $empty -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Cleaning previous runs..."
Wipe-Dir $dest
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$xDirs  = "build .dart_tool .gradle .idea node_modules .firebase ephemeral .plugin_symlinks .symlinks .kotlin"
$xFiles = "*.apk *.aab *.zip *.jks *.lnk dart-sdk.zip"

# ─── Flutter app helper ───────────────────────────────────────────────────────
$apps = @("customer_app", "delivery_app", "vendor_app")
foreach ($app in $apps) {
    Write-Host "Packaging $app..."
    $s = "$root\$app"
    $d = "$dest\$app"
    robocopy "$s\lib"     "$d\lib"     /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
    robocopy "$s\assets"  "$d\assets"  /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
    robocopy "$s\android" "$d\android" /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
    robocopy "$s\ios"     "$d\ios"     /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
    if (Test-Path "$s\pubspec.yaml")          { Copy-Item "$s\pubspec.yaml"          "$d\" -Force }
    if (Test-Path "$s\pubspec.lock")          { Copy-Item "$s\pubspec.lock"          "$d\" -Force }
    if (Test-Path "$s\analysis_options.yaml") { Copy-Item "$s\analysis_options.yaml" "$d\" -Force }
}

# ─── Admin Panel ─────────────────────────────────────────────────────────────
Write-Host "Packaging admin-panel..."
$s = "$root\admin-panel"
$d = "$dest\admin-panel"
robocopy "$s\src"    "$d\src"    /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
robocopy "$s\public" "$d\public" /E /XD $xDirs /XF $xFiles /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
foreach ($f in @("package.json","package-lock.json","vite.config.js","eslint.config.js","index.html")) {
    if (Test-Path "$s\$f") { Copy-Item "$s\$f" "$d\" -Force }
}

# ─── Landing Website ─────────────────────────────────────────────────────────
Write-Host "Packaging landing_website..."
$s = "$root\landing_website"
$d = "$dest\landing_website"
New-Item -ItemType Directory -Path $d -Force | Out-Null
foreach ($f in @("index.html","menu.html","univ_logo.png")) {
    if (Test-Path "$s\$f") { Copy-Item "$s\$f" "$d\" -Force }
}
if (Test-Path "$s\legal") {
    robocopy "$s\legal" "$d\legal" /E /NFL /NDL /NJH /NJS /R:0 /W:0 | Out-Null
}

# ─── Firebase Functions ───────────────────────────────────────────────────────
Write-Host "Packaging firebase-functions..."
$s = "$root\firebase-functions\functions"
$d = "$dest\firebase-functions\functions"
New-Item -ItemType Directory -Path $d -Force | Out-Null
foreach ($f in @("index.js","package.json","package-lock.json")) {
    if (Test-Path "$s\$f") { Copy-Item "$s\$f" "$d\" -Force }
}

# ─── Root docs + config + key SQL scripts ────────────────────────────────────
Write-Host "Copying root files..."
$rootFiles = @(
    "firebase.json", ".firebaserc", "codemagic.yaml", "HANDOVER.md",
    "COMPLETE_DB_SETUP.sql",
    "COMPLETE_REALTIME_FIX_ALL_APPS.sql",
    "MASTER_NOTIFICATION_SYSTEM.sql",
    "MASTER_SCHEMA_V12.sql",
    "COMPLETE_ORDER_TRACKING_FIX.sql",
    "FIX_RLS_POLICIES.sql"
)
foreach ($f in $rootFiles) {
    if (Test-Path "$root\$f") { Copy-Item "$root\$f" "$dest\" -Force }
}

# ─── Show what we have ───────────────────────────────────────────────────────
Write-Host "Package contents:"
Get-ChildItem $dest | Format-Table Name, LastWriteTime -AutoSize

# ─── ZIP ─────────────────────────────────────────────────────────────────────
Write-Host "Creating ZIP..."
Compress-Archive -Path "$dest\*" -DestinationPath $zipFile -Force

# ─── Cleanup ─────────────────────────────────────────────────────────────────
Write-Host "Cleaning temp..."
Wipe-Dir $dest

$sizeMB = [math]::Round((Get-Item $zipFile).Length / 1MB, 1)
Write-Host "DONE: $zipFile ($sizeMB MB)"
