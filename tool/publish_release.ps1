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
# release, then uploads the phone app, the Windows installer, the Windows zip and the user guide
# (docs\USER_GUIDE.md with its pictures from docs\images, attached as HomeTunes-README.md). The release page shows "What's new"
# (the text in -NotesFile, if given) followed by the whole user guide. Running it again updates
# the page text and the guide, and skips builds already uploaded. Use -UpdateOnly to refresh just
# the text and guide of an existing release.
#
# It signs in with the GitHub login git already uses on this PC (Windows Credential Manager),
# so no extra tools are needed. The login is never printed. The builds themselves are not
# committed to git: releases keep large files out of the code history.
param([string]$Version, [string]$NotesFile, [switch]$UpdateOnly)
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
if (-not $UpdateOnly) { foreach ($f in $files) { if (-not (Test-Path $f)) { throw "Missing $f - build it first." } } }

# HomeTunes (0.1.21, security review #1): never publish a phone app signed with the debug key.
# An update has to be signed with the same key as the installed copy, so a debug-signed APK
# would force everyone to uninstall later.
$apk = $files[0]
if (Test-Path $apk) {
  $apksigner = Get-ChildItem "$env:LOCALAPPDATA\Android\sdk\build-tools\*\apksigner.bat" -ErrorAction SilentlyContinue |
    Sort-Object { [version]($_.Directory.Name -replace '[^0-9.].*$', '') } | Select-Object -Last 1
  if (-not $apksigner) { throw 'apksigner not found in the Android SDK build-tools; cannot check how the APK is signed.' }
  # apksigner needs Java; Android Studio comes with one.
  if (-not $env:JAVA_HOME -and -not (Get-Command java -ErrorAction SilentlyContinue)) {
    $jbr = "$env:ProgramFiles\Android\Android Studio\jbr"
    if (Test-Path $jbr) { $env:JAVA_HOME = $jbr }
  }
  # apksigner may print warnings on stderr; don't let 'Stop' turn those into errors.
  $ErrorActionPreference = 'Continue'
  $certs = (& $apksigner.FullName verify --print-certs $apk 2>&1 | ForEach-Object { "$_" }) -join "`n"
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw "The APK's signature doesn't verify:`n$certs" }
  if ($certs -match 'CN=Android Debug') { throw 'The APK is signed with the debug key. Build it with android\key.properties in place.' }
}

# HomeTunes (0.1.21, security review #9): SHA-256 checksums of the downloads, uploaded as a file
# and shown at the end of the release page, so a download can be checked with Get-FileHash.
$sumsFile = "build\dist\HomeTunes-$Version-SHA256SUMS.txt"
$present = @($files | Where-Object { Test-Path $_ })
$checksums = ''
if ($present.Count -gt 0) {
  $lines = foreach ($f in $present) { "$((Get-FileHash -Algorithm SHA256 $f).Hash.ToLower())  $(Split-Path $f -Leaf)" }
  [IO.File]::WriteAllText((Join-Path (Get-Location) $sumsFile), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
  $checksums = "`n`n---`n`n## Checksums (SHA-256)`n`nTo check a download on Windows: ``Get-FileHash <file>`` in PowerShell, and compare with the line below.`n`n``````text`n" + ($lines -join "`n") + "`n```````n"
}

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'No GitHub sign-in found for git.' }
$h = @{ Authorization = "token $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'hometunes-release' }

git fetch -q origin
$sha = (git rev-parse origin/main).Trim()
if (-not (git tag --list $tag)) { git tag -a $tag $sha -m "HomeTunes $Version" }
git push -q origin $tag 2>&1 | Out-Null

# Page text: what's new in this version, then the user guide (with the version filled in).
$guide = (Get-Content docs\USER_GUIDE.md -Raw -Encoding UTF8) -replace '<version>', $Version
# Pictures live in docs\images (committed to main); the release page needs their full address.
$guide = $guide -replace '\]\(images/', "](https://github.com/$repo/raw/main/docs/images/"
$notes = ''
if ($NotesFile) { $notes = "## What's new in $Version`n`n" + (Get-Content $NotesFile -Raw -Encoding UTF8).Trim() + "`n`n---`n`n" }
$notes += $guide + $checksums
$guideFile = Join-Path $env:TEMP 'HomeTunes-README.md'
[IO.File]::WriteAllText($guideFile, $guide, (New-Object Text.UTF8Encoding $false))
# JSON bodies are sent as UTF-8 bytes; Windows PowerShell would otherwise mangle non-English characters.
# (The leading comma stops PowerShell turning the bytes into a list of separate objects.)
function Utf8Json($o) { ,[Text.Encoding]::UTF8.GetBytes(($o | ConvertTo-Json)) }
$json = 'application/json; charset=utf-8'

try {
  $rel = Invoke-RestMethod -Headers $h "https://api.github.com/repos/$repo/releases/tags/$tag"
  if (-not $NotesFile) {
    # Keep the existing "What's new" part when no new notes are given.
    $i = $rel.body.IndexOf("`n---`n")
    if ($rel.body.StartsWith("## What's new") -and $i -gt 0) { $notes = $rel.body.Substring(0, $i).TrimEnd() + "`n`n---`n`n" + $guide + $checksums }
  }
  $rel = Invoke-RestMethod -Method Patch -Headers $h -ContentType $json -Body (Utf8Json @{ body = $notes }) "https://api.github.com/repos/$repo/releases/$($rel.id)"
  if ($rel.body.Trim() -ne $notes.Trim()) { throw 'GitHub did not take the new page text.' }
  "Release $tag already existed: page text updated"
} catch {
  if ($_.Exception.Response.StatusCode.value__ -ne 404) { throw }
  $rel = Invoke-RestMethod -Method Post -Headers $h -ContentType $json `
    -Body (Utf8Json @{ tag_name = $tag; name = "HomeTunes $Version"; body = $notes; make_latest = 'true' }) "https://api.github.com/repos/$repo/releases"
  "Release $tag created"
}

# The guide is replaced each time, so it always matches the page.
$old = $rel.assets | Where-Object { $_.name -eq 'HomeTunes-README.md' }
if ($old) { Invoke-RestMethod -Method Delete -Headers $h "https://api.github.com/repos/$repo/releases/assets/$($old.id)" | Out-Null }
$url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=HomeTunes-README.md"
Invoke-RestMethod -Method Post -Headers $h -ContentType 'text/markdown; charset=utf-8' -InFile $guideFile $url | Out-Null
'Uploaded: HomeTunes-README.md (user guide)'
# The checksum file is replaced each time too, so it always matches the uploaded builds.
if (Test-Path $sumsFile) {
  $sumsName = Split-Path $sumsFile -Leaf
  $old = $rel.assets | Where-Object { $_.name -eq $sumsName }
  if ($old) { Invoke-RestMethod -Method Delete -Headers $h "https://api.github.com/repos/$repo/releases/assets/$($old.id)" | Out-Null }
  $url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=$sumsName"
  Invoke-RestMethod -Method Post -Headers $h -ContentType 'text/plain; charset=utf-8' -InFile $sumsFile $url | Out-Null
  "Uploaded: $sumsName"
}
if ($UpdateOnly) { "Page: $($rel.html_url)"; return }

foreach ($f in $files) {
  $name = Split-Path $f -Leaf
  if ($rel.assets | Where-Object { $_.name -eq $name }) { "Already uploaded: $name"; continue }
  $url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=$name"
  $a = Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/octet-stream' -InFile $f -TimeoutSec 900 $url
  "Uploaded: $name ($([math]::Round($a.size / 1MB, 1)) MB)"
}
"Page: $($rel.html_url)"
