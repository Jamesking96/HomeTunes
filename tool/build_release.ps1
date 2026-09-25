# Builds a shareable Windows release of HomeTunes.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -SkipBuild   # reuse last build
#
# Output in build\dist\:
#   HomeTunes-<version>-windows.zip      portable: unzip and run hometunes.exe
#   HomeTunes-Setup-<version>.exe        installer (needs Inno Setup 6 installed)
#
# Steps: build with Flutter -> copy the Visual C++ runtime DLLs in -> zip -> Inno Setup
# installer (installer\hometunes.iss). The version number comes from pubspec.yaml, so bump it
# there before building.

# -SkipBuild: package the existing build\windows\...\Release folder without rebuilding.
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'

# This script lives in tool\, so the project root is its parent folder.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Version from pubspec.yaml, e.g. "0.1.0+1" -> "0.1.0"
$fullVersion = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
# The part after "+" is the build number (used by Android); only the "0.1.0" part is shown.
$version = $fullVersion.Split('+')[0]
Write-Host "HomeTunes $version" -ForegroundColor Cyan

# 1. Build
if (-not $SkipBuild) {
    Write-Host "Building Windows release..." -ForegroundColor Cyan
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
}
$release = Join-Path $root 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $release 'hometunes.exe'))) { throw "No build found in $release" }

# 2. Visual C++ runtime next to the exe, so it runs on PCs without the VC++ Redistributable
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    $src = Join-Path $env:WINDIR "System32\$dll"
    if (Test-Path $src) { Copy-Item $src $release -Force }
    else { Write-Warning "$dll not found in System32; users may need the VC++ Redistributable" }
}

# 3. Portable zip (contains a HomeTunes\ folder)
$dist = Join-Path $root 'build\dist'
New-Item -ItemType Directory -Force $dist | Out-Null
# Copy into a "HomeTunes" folder first so the zip unpacks into a tidy folder rather than
# spilling files wherever the user extracts it.
$stage = Join-Path $dist 'HomeTunes'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
Copy-Item $release $stage -Recurse
$zip = Join-Path $dist "HomeTunes-$version-windows.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip
Remove-Item $stage -Recurse -Force
Write-Host "Zip:       $zip" -ForegroundColor Green

# 4. Installer
# Look for the Inno Setup compiler: on PATH first, then its usual install folders
# (all-users, 64-bit Program Files, and per-user installs e.g. from winget).
$iscc = @(
    (Get-Command iscc -ErrorAction SilentlyContinue).Source,
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if ($iscc) {
    # Pass the version and folders in as /D defines; the .iss file has defaults for running by hand.
    & $iscc /Q "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$dist" (Join-Path $root 'installer\hometunes.iss')
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    Write-Host "Installer: $(Join-Path $dist "HomeTunes-Setup-$version.exe")" -ForegroundColor Green
} else {
    Write-Warning "Inno Setup 6 not found, so only the zip was made. Install it with:  winget install JRSoftware.InnoSetup"
}
