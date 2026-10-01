# Third-party notices

HomeTunes' own code is under the MIT License (see [LICENSE](LICENSE)). HomeTunes is built with,
and its downloads include, software made by other people under their own licences. Those are
listed here. The complete list, with the full text of every licence (including every package
these depend on and the Flutter engine's own components), is in the app under
**Settings › About › Licences**.

## Playback engine: libmpv and FFmpeg (LGPL 3.0 or later)

Music and video play through [mpv](https://mpv.io) (as the libmpv library) with
[FFmpeg](https://ffmpeg.org), via the media_kit package. Since 0.1.40 this is media_kit's
**video** build of the engine. It is included as a separate shared library:

| Download | File | Version | Built by |
|---|---|---|---|
| Windows (installer and zip) | `libmpv-2.dll` | mpv v0.36.0-403-g652a1dd907, FFmpeg n6.0 | [media-kit/libmpv-win32-video-build](https://github.com/media-kit/libmpv-win32-video-build), release 2023-09-24 (its recipe at commit 87bb9596 matches the settings the file records) |
| Android (`.apk`) | `lib/<cpu>/libmpv.so` | mpv commit 78d43740, FFmpeg n6.0 | [media-kit/libmpv-android-video-build](https://github.com/media-kit/libmpv-android-video-build), v1.1.7 ("default" flavour) |

Both files record how they were built: mpv with `-Dgpl=false`, FFmpeg with `--disable-gpl
--disable-nonfree --enable-version3` (each FFmpeg part reports "LGPL version 3 or later"). So the
engine is licensed under the **GNU Lesser General Public License, version 3 or later**. Its
LGPL parts are:

| Part | Licence | In |
|---|---|---|
| mpv | LGPL 2.1 or later (built without its GPL parts) | Windows and Android |
| FFmpeg 6.0 | LGPL 3.0 or later | Windows and Android |
| [GNU FriBidi](https://github.com/fribidi/fribidi) 1.0.13 (Windows), 1.0.12 (Android) | LGPL 2.1 or later | Windows and Android |
| [libsoxr](https://sourceforge.net/projects/soxr/) | LGPL 2.1 or later | Windows |
| [GNU libiconv](https://www.gnu.org/software/libiconv/) 1.17 | LGPL 2.1 or later | Windows |
| [uchardet](https://www.freedesktop.org/wiki/Software/uchardet/) | MPL 1.1 / GPL 2.0 or later / LGPL 2.1 or later, used under the LGPL | Windows |

The LGPL text is in [licenses/LGPL-3.0.txt](licenses/LGPL-3.0.txt), and the GNU General Public
License it builds on is in [licenses/GPL-3.0.txt](licenses/GPL-3.0.txt). Both are also in the
app's Licences page, and next to `hometunes.exe` in the Windows downloads.

- **Source code:** every HomeTunes release on GitHub has **`HomeTunes-audio-engine-source.zip`**
  next to its downloads (the name is from when the engine played audio only). It has the source
  of all the LGPL parts above, exactly as built into the files where the build records it, plus
  both build recipes with their patches. The Windows build took libsoxr and uchardet from their
  git repositories without recording which commit, so the zip has the source the recipe points
  to and the nearest release. It's made by `tool/engine_source.ps1`, which lists where each part
  comes from. HomeTunes does not change any of them.
- **Other libraries built in:** libass, HarfBuzz, FreeType, dav1d, Mbed TLS and libxml2 (both
  platforms), and on Windows also libjxl, Highway, libvpl, libbs2b, libwebp, zimg, Speex,
  libmysofa, shaderc, glslang, SPIRV-Tools, SPIRV-Cross, Little CMS, libarchive, bzip2,
  libjpeg-turbo, libpng, zlib, fontconfig, libunibreak, MuJS, xxHash and the AMD AMF and NVIDIA
  codec headers. They are under permissive licences (ISC, MIT, BSD, Apache 2.0, zlib, FreeType
  and similar). Every one, with its licence text, is in
  [licenses/ENGINE-COMPONENTS.txt](licenses/ENGINE-COMPONENTS.txt), which is also in the app's
  Licences page ("Playback engine: other libraries") and next to `hometunes.exe`.
- **Replacing it:** HomeTunes loads the library at run time, so you can swap `libmpv-2.dll` (or
  `libmpv.so`) for your own build of a compatible version.
- **Copyright:** mpv is copyright its contributors (see
  [mpv's Copyright file](https://github.com/mpv-player/mpv/blob/master/Copyright)); FFmpeg is
  copyright the FFmpeg developers; the other parts are copyright their authors, as listed in
  their licence texts.

## Video drawing on Windows

To draw video, media_kit puts these files next to `hometunes.exe` in the Windows downloads
(from [flutter-windows-ANGLE-OpenGL-ES](https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES)
v1.0.1). Their licence texts are in [licenses/ENGINE-COMPONENTS.txt](licenses/ENGINE-COMPONENTS.txt).

| File | What it is | Licence |
|---|---|---|
| `libEGL.dll`, `libGLESv2.dll` | [ANGLE](https://chromium.googlesource.com/angle/angle) | BSD 3-Clause |
| `vk_swiftshader.dll` | [SwiftShader](https://github.com/google/swiftshader) | Apache 2.0 |
| `vulkan-1.dll` | [Vulkan Loader](https://github.com/KhronosGroup/Vulkan-Loader) | Apache 2.0 |
| `zlib.dll` | [zlib](https://zlib.net) | zlib |
| `d3dcompiler_47.dll` | Microsoft's Direct3D shader compiler | Microsoft; passed on under the Windows SDK's redistribution terms |

## Code kept in this repository

Two packages are kept in `packages/` as modified copies. Each keeps its original licence file,
and `HOMETUNES_CHANGES.md` in each folder describes what HomeTunes changed.

| Folder | Original | Licence |
|---|---|---|
| `packages/audio_metadata_reader` | [audio_metadata_reader](https://pub.dev/packages/audio_metadata_reader) 1.8.0, copyright (c) 2023 Clément Béal | MIT |
| `packages/audio_service_win` | [audio_service_win](https://github.com/HemantKArya/audio_service_win) 0.0.3, copyright (c) 2025 Hemant KArya | MIT |

## Packages from pub.dev

| Package | Version | Licence | Copyright |
|---|---|---|---|
| [Flutter](https://flutter.dev) and the Dart SDK | 3.47.5 | BSD 3-Clause | The Flutter Authors, the Dart project authors |
| [media_kit](https://pub.dev/packages/media_kit), media_kit_video, media_kit_libs_video, media_kit_libs_windows_video, media_kit_libs_android_video | 1.2.6, 2.0.1, 1.0.7, 1.0.11, 1.3.8 | MIT | Hitesh Kumar Saini |
| [image](https://pub.dev/packages/image) (video thumbnails) | 4.10.1 | MIT | Brendan Duncan |
| [audio_service](https://pub.dev/packages/audio_service) | 0.18.19 | MIT | Ryan Heise and the project contributors |
| [file_picker](https://pub.dev/packages/file_picker) | 13.1.0 | MIT | Miguel Ruivo |
| [permission_handler_android](https://pub.dev/packages/permission_handler_android) | 14.1.0 | MIT | Baseflow |
| [provider](https://pub.dev/packages/provider) | 6.1.5+1 | MIT | Remi Rousselet |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 11.2.0 | BSD 3-Clause | German Saprykin |
| [path_provider](https://pub.dev/packages/path_provider) | 2.1.6 | BSD 3-Clause | The Flutter Authors |
| [package_info_plus](https://pub.dev/packages/package_info_plus) | 10.2.1 | BSD 3-Clause | The Chromium Authors |
| [http](https://pub.dev/packages/http) | 1.6.0 | BSD 3-Clause | The Dart project authors |
| [crypto](https://pub.dev/packages/crypto) | 3.0.7 | BSD 3-Clause | The Dart project authors |

These also bring in smaller packages of their own; all of them, and their licence texts, are
listed in the app's Licences page.

## Microsoft Visual C++ runtime

The Windows downloads include `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll` from
the Microsoft Visual C++ Redistributable, so HomeTunes runs on a PC that doesn't have it. They
are Microsoft's, shared under the Visual Studio licence terms that allow them to be passed on
with programs that need them.

## Online services

HomeTunes can look things up online when you switch that on: MusicBrainz and the Cover Art
Archive (covers and song details), Open Library (book covers), and LRCLIB (lyrics). Their data
comes under each service's own terms; HomeTunes doesn't include any of it in its downloads.
