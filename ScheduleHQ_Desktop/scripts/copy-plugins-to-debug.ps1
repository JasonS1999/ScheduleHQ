# Copy plugin DLLs from install folder to Debug runner folder
# This ensures the Debug exe can run with all required plugins

$buildDir = "e:\ScheduleHQ\ScheduleHQ_Desktop\build\windows\x64"
$installDir = "$buildDir\install"
$debugDir = "$buildDir\runner\Debug"

Write-Host "Copying plugins from install folder to Debug folder..." -ForegroundColor Cyan

# Create Debug folder if it doesn't exist
if (!(Test-Path $debugDir)) {
    New-Item -ItemType Directory -Path $debugDir | Out-Null
}

# Copy all DLLs from install folder
$dlls = Get-ChildItem "$installDir\*.dll" -ErrorAction SilentlyContinue
foreach ($dll in $dlls) {
    Copy-Item $dll.FullName -Destination $debugDir -Force
    Write-Host "  Copied: $($dll.Name)" -ForegroundColor Green
}

# Copy data folder if it exists
if (Test-Path "$installDir\data") {
    Copy-Item "$installDir\data" -Destination $debugDir -Recurse -Force
    Write-Host "  Copied: data folder" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! Debug folder now has all required plugins." -ForegroundColor Green
