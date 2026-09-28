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
$notes += $guide
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
    if ($rel.body.StartsWith("## What's new") -and $i -gt 0) { $notes = $rel.body.Substring(0, $i).TrimEnd() + "`n`n---`n`n" + $guide }
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
if ($UpdateOnly) { "Page: $($rel.html_url)"; return }

foreach ($f in $files) {
  $name = Split-Path $f -Leaf
  if ($rel.assets | Where-Object { $_.name -eq $name }) { "Already uploaded: $name"; continue }
  $url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=$name"
  $a = Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/octet-stream' -InFile $f -TimeoutSec 900 $url
  "Uploaded: $name ($([math]::Round($a.size / 1MB, 1)) MB)"
}
"Page: $($rel.html_url)"
