# Puts the finished builds on GitHub as a Release, so they can be downloaded from
# https://github.com/Jamesking96/HomeTunes/releases (the newest one is marked "Latest").
#
#   powershell -ExecutionPolicy Bypass -File tool\publish_release.ps1 -NotesFile C:\Temp\ht\notes.md
#
# Before running: build everything for this version (tool\build_release.ps1 for Windows and
# `flutter build apk --release` copied to build\dist\HomeTunes-<version>-android.apk), and merge
# and push main. The version comes from pubspec.yaml unless -Version is given.
#
# What it does: tags the current origin/main as v<version> and pushes the tag, creates the
# release (with the text in -NotesFile, if given), then uploads the phone app, the Windows
# installer and the Windows zip from build\dist. Running it again skips anything already there.
#
# It signs in with the GitHub login git already uses on this PC (Windows Credential Manager),
# so no extra tools are needed. The login is never printed. The builds themselves are not
# committed to git: releases keep large files out of the code history.
param([string]$Version, [string]$NotesFile)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$repo = 'Jamesking96/HomeTunes'

if (-not $Version) {
  $line = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)' | Select-Object -First 1
  $Version = $line.Matches[0].Groups[1].Value
}
$tag = "v$Version"
$files = "build\dist\HomeTunes-$Version-android.apk", "build\dist\HomeTunes-Setup-$Version.exe",
         "build\dist\HomeTunes-$Version-windows.zip"
foreach ($f in $files) { if (-not (Test-Path $f)) { throw "Missing $f - build it first." } }

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'No GitHub sign-in found for git.' }
$h = @{ Authorization = "token $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'hometunes-release' }

git fetch -q origin
$sha = (git rev-parse origin/main).Trim()
if (-not (git tag --list $tag)) { git tag -a $tag $sha -m "HomeTunes $Version" }
git push -q origin $tag 2>&1 | Out-Null

$notes = @"
**Downloads**
- **Android phone:** HomeTunes-$Version-android.apk. Open it on the phone to install or update (your library and settings are kept).
- **Windows PC (installer):** HomeTunes-Setup-$Version.exe
- **Windows PC (no install):** HomeTunes-$Version-windows.zip. Unzip it and run hometunes.exe.
"@
if ($NotesFile) { $notes += "`n`n" + (Get-Content $NotesFile -Raw) }

try {
  $rel = Invoke-RestMethod -Headers $h "https://api.github.com/repos/$repo/releases/tags/$tag"
  "Release $tag already exists"
} catch {
  $body = @{ tag_name = $tag; name = "HomeTunes $Version"; body = $notes; make_latest = 'true' } | ConvertTo-Json
  $rel = Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/json' -Body $body "https://api.github.com/repos/$repo/releases"
  "Release $tag created"
}

foreach ($f in $files) {
  $name = Split-Path $f -Leaf
  if ($rel.assets | Where-Object { $_.name -eq $name }) { "Already uploaded: $name"; continue }
  $url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=$name"
  $a = Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/octet-stream' -InFile $f -TimeoutSec 900 $url
  "Uploaded: $name ($([math]::Round($a.size / 1MB, 1)) MB)"
}
"Page: $($rel.html_url)"
