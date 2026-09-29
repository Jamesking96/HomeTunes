# Switches branches only when it's safe: nothing unsaved in the working folder, and no
# HomeTunes debug run (VS Code F5 / flutter run) going. Use this instead of a bare
# `git checkout` / `git switch`, from any session (added 29 Sep 2026 after a session switched
# the folder to main while another session had unsaved edits on feature/advanced-themes; the
# edits came along by luck, because both branches were on the same commit).
#
#   powershell -ExecutionPolicy Bypass -File tool\switch_branch.ps1 <branch> [-New] [-From <base>]
#
# -New        create the branch (from -From, default: the current commit)
# -Force      switch even with unsaved changes (only when you made them yourself)
param(
  [Parameter(Mandatory = $true)][string]$Branch,
  [switch]$New,
  [string]$From,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$current = (git branch --show-current).Trim()
if ($current -eq $Branch) { "Already on $Branch."; return }

# 1. Unsaved changes: whoever made them is probably still working on them.
$dirty = @(git status --porcelain --untracked-files=normal | Where-Object { $_ -and $_ -notmatch '^\?\? build/' })
if ($dirty.Count -gt 0 -and -not $Force) {
  Write-Host "STOPPED: $($dirty.Count) unsaved change(s) on '$current':" -ForegroundColor Yellow
  $dirty | Select-Object -First 15 | ForEach-Object { "  $_" }
  Write-Host "Someone (another session, or VS Code) may be working on them. Ask before switching." -ForegroundColor Yellow
  Write-Host "If they are yours: commit them, or run again with -Force." -ForegroundColor Yellow
  exit 2
}

# 2. A debug run would be left running the wrong code (and a Windows build would fail).
$runs = @(Get-CimInstance Win32_Process | Where-Object {
  $_.ProcessId -ne $PID -and $_.CommandLine -match 'flutter_tools\.snapshot"? run|flutter\.bat"? run|run --machine'
})
if ($runs.Count -gt 0 -and -not $Force) {
  Write-Host "STOPPED: a flutter run / VS Code debug session is running. Ask before switching." -ForegroundColor Yellow
  exit 3
}

if ($New) {
  if ($From) { git switch -c $Branch $From } else { git switch -c $Branch }
} else {
  git switch $Branch
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
"Now on $(git branch --show-current) (was $current)."
