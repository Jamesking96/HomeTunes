// Licences shown in Settings › About › Licences (0.1.31; the video engine's in 0.1.40).
//
// Flutter's licence page already lists every Dart package HomeTunes uses (and HomeTunes' own
// MIT licence, from the LICENSE file at the top of the repository) and the Flutter engine's
// parts. It doesn't know about the playback engine, libmpv with FFmpeg and the libraries built
// into it, which media_kit downloads as a separate library (libmpv-2.dll / libmpv.so), nor the
// graphics files media_kit puts next to HomeTunes.exe on Windows. The engine is under the LGPL 3.0
// or later, which asks for its notice and licence text (plus the GPL it builds on) to come with
// the app, and the permissive libraries in it ask for their notices too, so
// [registerAppLicences] adds them from the bundled copies in licenses/. The same details are in
// THIRD_PARTY_NOTICES.md.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the licence page says about the playback engine, before the LGPL text.
const audioEngineNotice = '''
HomeTunes plays music and video with mpv (libmpv) and FFmpeg, included as a separate library
together with the libraries they use: libmpv-2.dll on Windows (mpv v0.36.0-403-g652a1dd907,
FFmpeg n6.0, built by media-kit/libmpv-win32-video-build) and libmpv.so on Android (mpv at
commit 78d43740, FFmpeg n6.0, built by media-kit/libmpv-android-video-build v1.1.7). They are
built without their GPL and nonfree parts, so the library is licensed under the GNU Lesser
General Public License, version 3 or later (below). Its LGPL parts are mpv, FFmpeg, GNU FriBidi
and, on Windows, libsoxr, GNU libiconv and uchardet. The other libraries in it, and the graphics
files next to HomeTunes.exe on Windows, are listed with their own licences under "Playback
engine: other libraries". HomeTunes does not change any of them, and you may replace the
library with your own build of a compatible version.

Source code: every HomeTunes release has HomeTunes-audio-engine-source.zip next to its
downloads, with the source of the LGPL parts at exactly these versions and the recipes that
built them: https://github.com/Jamesking96/HomeTunes/releases. The projects themselves are at
https://github.com/mpv-player/mpv, https://ffmpeg.org and https://github.com/fribidi/fribidi.

mpv is copyright its contributors. FFmpeg is copyright the FFmpeg developers. GNU FriBidi is
copyright its authors.''';

/// The line under the app's name at the top of the licence page.
const licenceLegalese = 'Copyright (c) 2026 Jamesking96. Free and open source under the MIT License.';

/// Paths of the bundled licence texts.
const lgplAsset = 'licenses/LGPL-3.0.txt';
const gplAsset = 'licenses/GPL-3.0.txt';
const engineComponentsAsset = 'licenses/ENGINE-COMPONENTS.txt';

/// The licence page's name for the list of the engine's other libraries.
const engineComponentsName = 'Playback engine: other libraries';

var _registered = false;

/// Adds the playback engine's licences to Flutter's licence list. Safe to call more than once.
void registerAppLicences({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => audioEngineLicences(bundle ?? rootBundle));
}

/// The playback engine's entries: its notice with the LGPL, the GPL the LGPL refers to, and every
/// other library in it with its licence text.
Stream<LicenseEntry> audioEngineLicences(AssetBundle bundle) async* {
  const packages = ['libmpv (mpv)', 'FFmpeg', 'GNU FriBidi', 'libsoxr', 'GNU libiconv', 'uchardet'];
  Future<String?> load(String asset) async {
    try {
      return await bundle.loadString(asset);
    } catch (e) {
      debugPrint('HomeTunes: licence text missing: $asset ($e)');
      return null;
    }
  }

  final lgpl = await load(lgplAsset), gpl = await load(gplAsset), components = await load(engineComponentsAsset);
  yield LicenseEntryWithLineBreaks(packages, '$audioEngineNotice\n\n${lgpl ?? 'GNU Lesser General Public License, '
      'version 3: https://www.gnu.org/licenses/lgpl-3.0.txt'}');
  yield LicenseEntryWithLineBreaks(
      packages, gpl ?? 'GNU General Public License, version 3: https://www.gnu.org/licenses/gpl-3.0.txt');
  yield LicenseEntryWithLineBreaks(
      const [engineComponentsName],
      components ??
          'The playback engine\'s other libraries and their licences: '
              'https://github.com/Jamesking96/HomeTunes/blob/main/licenses/ENGINE-COMPONENTS.txt');
}
