# Third-party notices

HomeTunes' own code is under the MIT License (see [LICENSE](LICENSE)). HomeTunes is built with,
and its downloads include, software made by other people under their own licences. Those are
listed here. The complete list, with the full text of every licence (including every package
these depend on and the Flutter engine's own components), is in the app under
**Settings › About › Licences**.

## Audio engine: libmpv and FFmpeg (LGPL 3.0 or later)

Playback uses [mpv](https://mpv.io) (as the libmpv library) with
[FFmpeg](https://ffmpeg.org), through the media_kit package. They are included as a separate
shared library:

| Download | File | Version | Built by |
|---|---|---|---|
| Windows (installer and zip) | `libmpv-2.dll` | mpv v0.36.0-403-g652a1dd907, FFmpeg n6.0 | [media-kit/libmpv-win32-audio-build](https://github.com/media-kit/libmpv-win32-audio-build), release 2023-09-24 |
| Android (`.apk`) | `lib/<cpu>/libmpv.so` | mpv 0.35.1, FFmpeg n6.0 | [media-kit/libmpv-android-audio-build](https://github.com/media-kit/libmpv-android-audio-build), v1.1.8 |

These builds have their GPL parts switched off (mpv `-Dgpl=false`; FFmpeg `--disable-gpl
--enable-version3`), so they are licensed under the **GNU Lesser General Public License,
version 3 or later**. The Windows file also includes [GNU FriBidi](https://github.com/fribidi/fribidi)
1.0.13 (LGPL 2.1 or later, used here under the LGPL 3.0). The LGPL text is in
[licenses/LGPL-3.0.txt](licenses/LGPL-3.0.txt), and the GNU General Public License it builds on
is in [licenses/GPL-3.0.txt](licenses/GPL-3.0.txt). Both are also in the app's Licences page,
and next to `hometunes.exe` in the Windows downloads.

- **Source code:** every HomeTunes release on GitHub has **`HomeTunes-audio-engine-source.zip`**
  next to its downloads: the source of mpv (commit 652a1dd9 for Windows, 0.35.1 for Android),
  FFmpeg 6.0 and FriBidi 1.0.13, exactly as built into the files above, plus both build-script
  repositories with their patches. It's made by `tool/engine_source.ps1`, which lists where
  each part comes from. The upstream projects are at <https://github.com/mpv-player/mpv>,
  <https://ffmpeg.org/download.html> and <https://github.com/fribidi/fribidi>. HomeTunes does
  not change them.
- **Other libraries built in** (mbedtls, libxml2, libass, HarfBuzz, FreeType, zlib, libpng,
  Little CMS, zimg, libjxl and similar) are under permissive licences (Apache 2.0, MIT, ISC,
  BSD, zlib, FreeType); their versions are set in the build scripts.
- **Replacing it:** HomeTunes loads the library at run time, so you can swap `libmpv-2.dll` (or
  `libmpv.so`) for your own build of a compatible version.
- **Copyright:** mpv is copyright its contributors (see
  [mpv's Copyright file](https://github.com/mpv-player/mpv/blob/master/Copyright)); FFmpeg is
  copyright the FFmpeg developers; GNU FriBidi is copyright its authors.

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
| [media_kit](https://pub.dev/packages/media_kit), media_kit_libs_audio, media_kit_libs_windows_audio, media_kit_libs_android_audio | 1.2.6, 1.0.7, 1.0.9, 1.3.8 | MIT | Hitesh Kumar Saini |
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
