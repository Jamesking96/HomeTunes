# Builds a shareable Windows release of HomeTunes.
#
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -SkipBuild   # reuse last build
#   powershell -ExecutionPolicy Bypass -File tool\build_release.ps1 -Android     # also the phone app
#
# Output in build\dist\:
#   HomeTunes-<version>-windows.zip      portable: unzip and run hometunes.exe
#   HomeTunes-Setup-<version>.exe        installer (needs Inno Setup 6 installed)
#   HomeTunes-<version>-android.apk      with -Android: signed with the key in android\key.properties
#
# Steps: build with Flutter -> copy the Visual C++ runtime DLLs in -> zip -> Inno Setup
# installer (installer\hometunes.iss). The version number comes from pubspec.yaml, so bump it
# there before building.

# -SkipBuild: package the existing build\windows\...\Release folder without rebuilding.
# -Android: also build the phone app and check it's signed with the HomeTunes release key.
param([switch]$SkipBuild, [switch]$Android)
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

# 2b. Licences next to the exe (0.1.31): HomeTunes' MIT licence, the third-party notices, and the
#     LGPL/GPL texts that must come with libmpv-2.dll. The zip and the installer both pick these up.
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $release 'LICENSE.txt') -Force
Copy-Item (Join-Path $root 'THIRD_PARTY_NOTICES.md') $release -Force
$licenceDir = Join-Path $release 'licenses'
New-Item -ItemType Directory -Force $licenceDir | Out-Null
Copy-Item (Join-Path $root 'licenses\*.txt') $licenceDir -Force

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

# 5. Phone app (HomeTunes 0.1.21, security review #1)
if ($Android) {
    if (-not (Test-Path (Join-Path $root 'android\key.properties'))) {
        throw 'android\key.properties is missing, so the APK cannot be signed with the HomeTunes release key.'
    }
    Write-Host "Building Android release..." -ForegroundColor Cyan
    # Gradle fails with "Unable to establish loopback connection" without a short temp folder.
    New-Item -ItemType Directory -Force 'C:\Temp\ht' | Out-Null
    $env:JAVA_TOOL_OPTIONS = '-Djdk.net.unixdomain.tmpdir=C:\Temp\ht'
    $env:GRADLE_OPTS = $env:JAVA_TOOL_OPTIONS
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }
    $apk = Join-Path $dist "HomeTunes-$version-android.apk"
    Copy-Item (Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk') $apk -Force
    # Refuse a debug-signed APK: it could never update a copy signed with the release key.
    $apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\sdk\build-tools\*\apksigner.bat" -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Directory.Name -replace '[^0-9.].*$', '') } | Select-Object -Last 1
    if ($apksigner) {
        # apksigner needs Java; Android Studio comes with one.
        if (-not $env:JAVA_HOME -and -not (Get-Command java -ErrorAction SilentlyContinue)) {
            $jbr = "$env:ProgramFiles\Android\Android Studio\jbr"
            if (Test-Path $jbr) { $env:JAVA_HOME = $jbr }
        }
        $ErrorActionPreference = 'Continue'
        $certs = (& $apksigner.FullName verify --print-certs $apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) { throw "The APK's signature doesn't verify:`n$certs" }
        if ($certs -match 'CN=Android Debug') { throw 'The APK came out signed with the debug key.' }
        ($certs -split "`n") | Where-Object { $_ -match 'certificate DN|SHA-256 digest' } | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Warning 'apksigner not found, so the APK signature was not checked.'
    }
    Write-Host "APK:       $apk" -ForegroundColor Green
}
