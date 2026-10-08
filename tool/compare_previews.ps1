# Checks that a change hasn't altered how the app looks (Phase 0 of the modular refactor, 8 Oct 2026).
# Draws every off-screen preview (tool\*preview*_test.dart) into a folder and compares each picture
# with the saved baseline, byte for byte. Pictures are drawn the same way every time on the same PC,
# so any difference means something on screen changed.
#   Make the baseline (before starting a change):
#     powershell -ExecutionPolicy Bypass -File tool\compare_previews.ps1 -MakeBaseline
#   Compare after the change (exit code 1 if any picture differs, is missing or is new):
#     powershell -ExecutionPolicy Bypass -File tool\compare_previews.ps1
param(
  [string]$Baseline = 'C:\Temp\ht\baseline',
  [string]$Out = 'C:\Temp\ht\compare',
  [switch]$MakeBaseline
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $env:PATH = "$env:USERPROFILE\flutter\bin;$env:PATH"
}
$target = if ($MakeBaseline) { $Baseline } else { $Out }
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force $target | Out-Null

$failed = @()
foreach ($t in Get-ChildItem (Join-Path $repo 'tool') -Filter '*preview*_test.dart') {
  Write-Host "Drawing $($t.Name)..."
  Push-Location $repo
  & flutter test "tool\$($t.Name)" "--dart-define=OUT=$target" *> (Join-Path $target "$($t.BaseName).log")
  $code = $LASTEXITCODE
  Pop-Location
  if ($code -ne 0) { $failed += $t.Name }
}
if ($failed) { Write-Host "These previews failed to draw: $($failed -join ', ') (see the .log files in $target)" -ForegroundColor Red; exit 2 }
$count = (Get-ChildItem $target -Filter *.png).Count
if ($MakeBaseline) { Write-Host "Baseline saved: $count pictures in $Baseline"; exit 0 }

$before = @{}; Get-ChildItem $Baseline -Filter *.png | ForEach-Object { $before[$_.Name] = (Get-FileHash $_.FullName).Hash }
$after = @{}; Get-ChildItem $Out -Filter *.png | ForEach-Object { $after[$_.Name] = (Get-FileHash $_.FullName).Hash }
$changed = @($before.Keys | Where-Object { $after.ContainsKey($_) -and $after[$_] -ne $before[$_] } | Sort-Object)
$missing = @($before.Keys | Where-Object { -not $after.ContainsKey($_) } | Sort-Object)
$new = @($after.Keys | Where-Object { -not $before.ContainsKey($_) } | Sort-Object)
if ($changed) { Write-Host "Changed: $($changed -join ', ')" -ForegroundColor Red }
if ($missing) { Write-Host "Missing: $($missing -join ', ')" -ForegroundColor Red }
if ($new) { Write-Host "New: $($new -join ', ')" -ForegroundColor Yellow }
if ($changed -or $missing -or $new) { exit 1 }
Write-Host "All $count pictures match the baseline." -ForegroundColor Green
