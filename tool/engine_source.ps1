# Makes build\dist\HomeTunes-audio-engine-source.zip: the source code of the LGPL parts of the
# audio engine that every HomeTunes download includes (libmpv-2.dll on Windows, libmpv.so on
# Android), at exactly the versions built into those files, plus the scripts that built them.
#
#   powershell -ExecutionPolicy Bypass -File tool\engine_source.ps1
#
# Why (0.1.31): the engine is under the LGPL 3.0 or later, which asks whoever shares it to make
# its source available too. tool\publish_release.ps1 attaches this zip to every release, next to
# the downloads. See THIRD_PARTY_NOTICES.md.
#
# The versions come from the engine files themselves (they record them): Windows (media-kit's
# libmpv-win32-audio-build, 2023-09-24) = mpv commit 652a1dd9, FFmpeg 6.0, FriBidi 1.0.13;
# Android (media-kit's libmpv-android-audio-build v1.1.8) = mpv 0.35.1, FFmpeg 6.0. The other
# libraries built in (mbedtls, libxml2, libass, HarfBuzz, FreeType, zlib, ...) are under
# permissive licences that don't ask for this. If media_kit's engine files change (a new
# media_kit_libs_* version), check the versions again and update this list.
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'build\dist'
$zip = Join-Path $dist 'HomeTunes-audio-engine-source.zip'
if ((Test-Path $zip) -and -not $Force) { "Already made: $zip"; return }

$work = Join-Path $root 'build\engine-source'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$pack = Join-Path $work 'HomeTunes-audio-engine-source'
New-Item -ItemType Directory -Force $pack | Out-Null

# name in the zip, where it comes from, what it is
$sources = @(
  @('mpv-652a1dd90711839acdccc08004056d25514ef2d8.tar.gz',
    'https://github.com/mpv-player/mpv/archive/652a1dd90711839acdccc08004056d25514ef2d8.tar.gz',
    'mpv as built into the Windows libmpv-2.dll (LGPL-2.1-or-later with -Dgpl=false)'),
  @('mpv-0.35.1.tar.gz',
    'https://github.com/mpv-player/mpv/archive/refs/tags/v0.35.1.tar.gz',
    'mpv as built into the Android libmpv.so, before the Android build''s patches (in the build scripts below)'),
  @('ffmpeg-6.0.tar.xz',
    'https://ffmpeg.org/releases/ffmpeg-6.0.tar.xz',
    'FFmpeg 6.0 (tag n6.0), in both (LGPL-3.0-or-later: --disable-gpl --enable-version3)'),
  @('fribidi-1.0.13.tar.xz',
    'https://github.com/fribidi/fribidi/releases/download/v1.0.13/fribidi-1.0.13.tar.xz',
    'GNU FriBidi 1.0.13, in the Windows libmpv-2.dll (LGPL-2.1-or-later)'),
  @('libmpv-win32-audio-build-f5a6f879.tar.gz',
    'https://github.com/media-kit/libmpv-win32-audio-build/archive/f5a6f879c9b8bef6a73e52c8c0f35e51636c96e5.tar.gz',
    'The Windows build scripts and patches as of that build (2023-09-24)'),
  @('libmpv-android-audio-build-v1.1.8.tar.gz',
    'https://github.com/media-kit/libmpv-android-audio-build/archive/refs/tags/v1.1.8.tar.gz',
    'The Android build scripts and patches (v1.1.8)')
)

$lines = @()
foreach ($s in $sources) {
  $dest = Join-Path $pack $s[0]
  Write-Host "Downloading $($s[0])..."
  Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'HomeTunes release' } $s[1] -OutFile $dest
  $size = (Get-Item $dest).Length
  if ($size -lt 50KB) { throw "$($s[0]) is only $size bytes; the download probably failed." }
  $hash = (Get-FileHash -Algorithm SHA256 $dest).Hash.ToLower()
  $lines += "- **$($s[0])** ($([math]::Round($size / 1MB, 1)) MB): $($s[2]).`n  From <$($s[1])>`n  SHA-256 ``$hash``"
}

Copy-Item (Join-Path $root 'licenses\LGPL-3.0.txt') $pack
Copy-Item (Join-Path $root 'licenses\GPL-3.0.txt') $pack
$readme = @"
# Source code of HomeTunes' audio engine

Every HomeTunes download includes an audio engine made from mpv and FFmpeg (and, on Windows,
GNU FriBidi): ``libmpv-2.dll`` in the Windows installer and zip, ``lib/<cpu>/libmpv.so`` in the
Android app. They are licensed under the GNU Lesser General Public License, version 3 or later
(``LGPL-3.0.txt`` and ``GPL-3.0.txt`` here). This is their source code, at the versions built
into those files, and the scripts (with their patches) that built them. HomeTunes itself doesn't
change any of it. HomeTunes' own code is MIT-licensed: https://github.com/Jamesking96/HomeTunes

The engine files were built by the media_kit project:
- Windows: https://github.com/media-kit/libmpv-win32-audio-build, release 2023-09-24
- Android: https://github.com/media-kit/libmpv-android-audio-build, v1.1.8

Other libraries built into the engine (mbedtls, libxml2, libass, HarfBuzz, FreeType, zlib and
similar) are under permissive licences; their versions are set in the build scripts.

## Files

$($lines -join "`n")
"@
[IO.File]::WriteAllText((Join-Path $pack 'README.md'), $readme, (New-Object Text.UTF8Encoding $false))

New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $pack -DestinationPath $zip
Remove-Item $work -Recurse -Force
"Made: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
