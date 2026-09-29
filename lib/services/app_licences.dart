// Licences shown in Settings › About › Licences (0.1.31).
//
// Flutter's licence page already lists every Dart package HomeTunes uses (and HomeTunes' own
// MIT licence, from the LICENSE file at the top of the repository) and the Flutter engine's
// parts. It doesn't know about the audio engine, libmpv with FFmpeg, which media_kit downloads
// as a separate library (libmpv-2.dll / libmpv.so). Those are under the LGPL 3.0 or later,
// which asks for its notice and licence text (plus the GPL it builds on) to come with the app,
// so [registerAppLicences] adds them from the bundled copies in licenses/. The same details are
// in THIRD_PARTY_NOTICES.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the licence page says about the audio engine, before the LGPL text.
const audioEngineNotice = '''
HomeTunes plays audio with mpv (libmpv) and FFmpeg, included as a separate library:
libmpv-2.dll on Windows (mpv v0.36.0-403-g652a1dd907, FFmpeg n6.0, built by
media-kit/libmpv-win32-audio-build) and libmpv.so on Android (mpv 0.35.1, FFmpeg n6.0, built by
media-kit/libmpv-android-audio-build). They are built without their GPL parts, so they are
licensed under the GNU Lesser General Public License, version 3 or later (below). HomeTunes does
not change them, and you may replace the library with your own build of a compatible version.

Source code: https://github.com/mpv-player/mpv and https://ffmpeg.org/download.html; the build
scripts are at https://github.com/media-kit/libmpv-win32-audio-build and
https://github.com/media-kit/libmpv-android-audio-build.

mpv is copyright its contributors. FFmpeg is copyright the FFmpeg developers.''';

/// The line under the app's name at the top of the licence page.
const licenceLegalese = 'Copyright (c) 2026 Jamesking96. Free and open source under the MIT License.';

/// Paths of the bundled licence texts.
const lgplAsset = 'licenses/LGPL-3.0.txt';
const gplAsset = 'licenses/GPL-3.0.txt';

var _registered = false;

/// Adds the audio engine's licences to Flutter's licence list. Safe to call more than once.
void registerAppLicences({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => audioEngineLicences(bundle ?? rootBundle));
}

/// The audio engine's entries: its notice with the LGPL, then the GPL the LGPL refers to.
Stream<LicenseEntry> audioEngineLicences(AssetBundle bundle) async* {
  const packages = ['libmpv (mpv)', 'FFmpeg'];
  String? lgpl, gpl;
  try {
    lgpl = await bundle.loadString(lgplAsset);
    gpl = await bundle.loadString(gplAsset);
  } catch (e) {
    debugPrint('HomeTunes: licence texts missing: $e');
  }
  yield LicenseEntryWithLineBreaks(packages, '$audioEngineNotice\n\n${lgpl ?? 'GNU Lesser General Public License, '
      'version 3: https://www.gnu.org/licenses/lgpl-3.0.txt'}');
  yield LicenseEntryWithLineBreaks(
      packages, gpl ?? 'GNU General Public License, version 3: https://www.gnu.org/licenses/gpl-3.0.txt');
}
