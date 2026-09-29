# Adds HomeTunes-audio-engine-source.zip (the audio engine's LGPL source code, from
# tool\engine_source.ps1) to releases that are already on GitHub (0.1.31). New releases get it
# from tool\publish_release.ps1; this is for ones published before that, or if it's missing.
#
#   powershell -ExecutionPolicy Bypass -File tool\attach_engine_source.ps1            # every release
#   powershell -ExecutionPolicy Bypass -File tool\attach_engine_source.ps1 -Tags v0.1.30
#
# Releases that already have it are skipped. Signs in the same way as publish_release.ps1 (the
# GitHub login git already uses on this PC); the login is never printed.
param([string[]]$Tags)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$repo = 'Jamesking96/HomeTunes'
$name = 'HomeTunes-audio-engine-source.zip'

& (Join-Path $PSScriptRoot 'engine_source.ps1')
$zip = Join-Path (Get-Location) "build\dist\$name"

$cred = "protocol=https`nhost=github.com`n`n" | git credential fill
$token = ($cred | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) { throw 'No GitHub sign-in found for git.' }
$h = @{ Authorization = "token $token"; Accept = 'application/vnd.github+json'; 'User-Agent' = 'hometunes-release' }

$releases = Invoke-RestMethod -Headers $h "https://api.github.com/repos/$repo/releases?per_page=100"
if ($Tags) { $releases = $releases | Where-Object { $Tags -contains $_.tag_name } }
foreach ($rel in $releases) {
  if ($rel.assets | Where-Object { $_.name -eq $name }) { "$($rel.tag_name): already has it"; continue }
  $url = "https://uploads.github.com/repos/$repo/releases/$($rel.id)/assets?name=$name"
  Invoke-RestMethod -Method Post -Headers $h -ContentType 'application/zip' -InFile $zip -TimeoutSec 900 $url | Out-Null
  "$($rel.tag_name): added"
}
