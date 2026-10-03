// Is the internet reachable? (0.1.50, the user asked: "Add a check on opening to see if the
// internet is reachable. If it is not, pop up with a warning about some features not working
// and allow them to carry on using the application. If they try to use an online feature,
// check again for the internet and give the same warning again if nothing has changed.")
//
// The check opens a plain connection (no data sent) to the sites HomeTunes already uses
// online: GitHub (updates, What's new), MusicBrainz (song and album details), LRCLIB (lyrics)
// and Open Library (book details and covers). Any one answering within a few seconds counts as
// online. Nothing else is contacted, so the check tells no new site anything.
//
// The warning itself is in ui/widgets/offline_warning.dart.
import 'dart:async';
import 'dart:io';

class InternetCheck {
  InternetCheck._();

  static const hosts = ['api.github.com', 'musicbrainz.org', 'lrclib.net', 'openlibrary.org'];

  /// Replaces the real check (tests). Under `flutter test` the default is "online", so tests
  /// never touch the network unless they set this.
  static Future<bool> Function()? override;

  /// The most recent answer (null before the first check).
  static bool? last;

  static bool get _underTest => Platform.environment.containsKey('FLUTTER_TEST');

  static Future<bool> reachable({Duration timeout = const Duration(seconds: 4)}) async {
    final probe = override;
    final bool ok;
    if (probe != null) {
      ok = await probe();
    } else if (_underTest) {
      ok = true;
    } else {
      ok = await _anyAnswers(timeout);
    }
    last = ok;
    return ok;
  }

  /// True as soon as any of [hosts] accepts a connection; false if none do within [timeout].
  static Future<bool> _anyAnswers(Duration timeout) {
    final done = Completer<bool>();
    var left = hosts.length;
    for (final host in hosts) {
      Socket.connect(host, 443, timeout: timeout).then((s) {
        s.destroy();
        if (!done.isCompleted) done.complete(true);
      }, onError: (_) {
        if (--left == 0 && !done.isCompleted) done.complete(false);
      });
    }
    // A safety net in case a lookup hangs past the connection timeout.
    return done.future.timeout(timeout + const Duration(seconds: 2), onTimeout: () => false);
  }
}
