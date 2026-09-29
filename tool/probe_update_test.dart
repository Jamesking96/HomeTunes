// Live check of "Check for updates" against the real GitHub release (goes online).
// Reads the latest release, downloads its Windows installer and checks it against the release's
// SHA256SUMS file, exactly as the app does. Nothing is installed.
//   flutter test tool/probe_update_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/update_checker.dart';

void main() {
  test('latest release: read it, download the installer and check it', () async {
    final checker = UpdateChecker();
    final r = await checker.fetchLatest();
    // ignore: avoid_print
    print('Latest: ${r.version}  page: ${r.page}\nWhat\'s new: ${r.whatsNew.split('\n').first}');
    var last = -1;
    final file = await checker.downloadInstaller(r, onProgress: (f) {
      final pct = ((f ?? 0) * 100).round();
      if (pct ~/ 25 != last ~/ 25) {
        last = pct;
        // ignore: avoid_print
        print('  $pct%');
      }
    });
    // ignore: avoid_print
    print('Checksum matched: ${file.path} (${await file.length()} bytes)');
    await file.delete();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
