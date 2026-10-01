# Makes build\dist\HomeTunes-audio-engine-source.zip: the source code of the LGPL parts of the
# playback engine that every HomeTunes download includes (libmpv-2.dll on Windows, libmpv.so on
# Android), at exactly the versions built into those files, plus the scripts that built them.
# (The file keeps its old name, from when the engine played audio only, so releases line up.)
#
#   powershell -ExecutionPolicy Bypass -File tool\engine_source.ps1
#
# Why (0.1.31): the engine is under the LGPL 3.0 or later, which asks whoever shares it to make
# its source available too. tool\publish_release.ps1 attaches this zip to every release, next to
# the downloads. See THIRD_PARTY_NOTICES.md.
#
# 0.1.40: the engine is now media_kit's VIDEO build (it plays music and video). The versions come
# from the engine files themselves (they record their build settings) and the build recipes:
#  - Windows: media-kit/libmpv-win32-video-build, release 2023-09-24 (mpv-dev-x86_64-20230924-git-
#    652a1dd.7z, set in media_kit_libs_windows_video 1.0.11). libmpv-2.dll records mpv
#    v0.36.0-403-g652a1dd907 (-Dgpl=false), FFmpeg n6.0 (--disable-gpl --disable-nonfree
#    --enable-version3), FriBidi 1.0.13, libjpeg-turbo 3.0.1, libpng 1.6.41, libarchive 3.7.3dev.
#    Its FFmpeg settings match the repo's recipe at commit 87bb9596 (28 Feb 2024; the next commit
#    turned libjxl off, which this DLL still has). LGPL parts: mpv, FFmpeg, FriBidi, libsoxr, GNU
#    libiconv 1.17 and uchardet (tri-licensed, used under the LGPL). libsoxr and uchardet are built
#    from their git repositories without a recorded commit, so the recipe's source and the nearest
#    release are both included.
#  - Android: media-kit/libmpv-android-video-build v1.1.7 (set in media_kit_libs_android_video
#    1.3.8, the "default" flavour). libmpv.so records FFmpeg n6.0 (LGPL 3), mpv -Dgpl=false at
#    commit 78d43740, FriBidi 1.0.12. LGPL parts: mpv, FFmpeg, FriBidi.
# The permissive libraries' licence texts are in licenses\ENGINE-COMPONENTS.txt (shown in the app).
# If media_kit's engine files change (a new media_kit_libs_* version), check all of this again.
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
  @('mpv-78d43740f52db817d98bcf24fb30a76ab6fa13ff.tar.gz',
    'https://github.com/mpv-player/mpv/archive/78d43740f52db817d98bcf24fb30a76ab6fa13ff.tar.gz',
    'mpv as built into the Android libmpv.so (LGPL-2.1-or-later with -Dgpl=false), before the Android build''s patches (in the build scripts below)'),
  @('ffmpeg-6.0.tar.xz',
    'https://ffmpeg.org/releases/ffmpeg-6.0.tar.xz',
    'FFmpeg 6.0 (tag n6.0), in both (LGPL-3.0-or-later: --disable-gpl --disable-nonfree --enable-version3)'),
  @('fribidi-1.0.13.tar.xz',
    'https://github.com/fribidi/fribidi/releases/download/v1.0.13/fribidi-1.0.13.tar.xz',
    'GNU FriBidi 1.0.13, in the Windows libmpv-2.dll (LGPL-2.1-or-later)'),
  @('fribidi-1.0.12.tar.xz',
    'https://github.com/fribidi/fribidi/releases/download/v1.0.12/fribidi-1.0.12.tar.xz',
    'GNU FriBidi 1.0.12, in the Android libmpv.so (LGPL-2.1-or-later)'),
  @('libiconv-1.17.tar.gz',
    'https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz',
    'GNU libiconv 1.17, in the Windows libmpv-2.dll (the library is LGPL-2.1-or-later)'),
  @('soxr-shinchiro-fork.tar.gz',
    'https://gitlab.com/shinchiro/soxr/-/archive/master/soxr-master.tar.gz',
    'libsoxr from the fork the Windows build uses (LGPL-2.1-or-later); the build took the fork''s latest code at the time and doesn''t record which commit'),
  @('soxr-0.1.3-Source.tar.xz',
    'https://downloads.sourceforge.net/project/soxr/soxr-0.1.3-Source.tar.xz',
    'libsoxr 0.1.3, the latest release of libsoxr itself (LGPL-2.1-or-later)'),
  @('uchardet-0.0.8.tar.xz',
    'https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz',
    'uchardet 0.0.8 (MPL-1.1 / GPL-2.0-or-later / LGPL-2.1-or-later, used under the LGPL), in the Windows libmpv-2.dll; the build took the project''s latest code at the time and doesn''t record which commit, so this is the nearest release'),
  @('libmpv-win32-video-build-87bb9596.tar.gz',
    'https://github.com/media-kit/libmpv-win32-video-build/archive/87bb9596060aef5ffe1a3f1f32ad16958bfca2d6.tar.gz',
    'The Windows build recipe and patches: the commit whose settings match the ones libmpv-2.dll records'),
  @('libmpv-android-video-build-v1.1.7.tar.gz',
    'https://github.com/media-kit/libmpv-android-video-build/archive/refs/tags/v1.1.7.tar.gz',
    'The Android build scripts and patches (v1.1.7, "default" flavour)')
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
Copy-Item (Join-Path $root 'licenses\ENGINE-COMPONENTS.txt') $pack
$readme = @"
# Source code of HomeTunes' playback engine

Every HomeTunes download includes a playback engine (for music and video) made from mpv and
FFmpeg with a number of other libraries: ``libmpv-2.dll`` in the Windows installer and zip,
``lib/<cpu>/libmpv.so`` in the Android app. It is built without its GPL and nonfree parts and is
licensed under the GNU Lesser General Public License, version 3 or later (``LGPL-3.0.txt`` and
``GPL-3.0.txt`` here). This is the source code of its LGPL parts (mpv, FFmpeg, GNU FriBidi and,
on Windows, libsoxr, GNU libiconv and uchardet), at the versions built into those files, and the
recipes (with their patches) that built them. HomeTunes itself doesn't change any of it.
HomeTunes' own code is MIT-licensed: https://github.com/Jamesking96/HomeTunes

The engine files were built by the media_kit project:
- Windows: https://github.com/media-kit/libmpv-win32-video-build, release 2023-09-24
- Android: https://github.com/media-kit/libmpv-android-video-build, v1.1.7

The other libraries in the engine (libass, HarfBuzz, FreeType, dav1d, Mbed TLS, libxml2 and
more) are under permissive licences; ``ENGINE-COMPONENTS.txt`` lists every one with its licence
text, and their versions are set in the build recipes.

## Files

$($lines -join "`n")
"@
[IO.File]::WriteAllText((Join-Path $pack 'README.md'), $readme, (New-Object Text.UTF8Encoding $false))

New-Item -ItemType Directory -Force $dist | Out-Null
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $pack -DestinationPath $zip
Remove-Item $work -Recurse -Force
"Made: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB)"
