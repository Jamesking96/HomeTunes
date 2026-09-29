// Tests for "Check for updates" (0.1.23): version comparison, reading GitHub's release JSON and
// the SHA256SUMS file, the "What's new" text, which download links are allowed, the once-a-day
// check in UpdateModel, and the installer download refusing a file whose checksum is wrong.
// GitHub is replaced by a fake http client, so nothing goes online.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/update_checker.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/ui/screens/settings/update_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A release like the ones tool/publish_release.ps1 makes.
Map<String, dynamic> releaseJson(String version, {bool prerelease = false}) {
  String dl(String name) => 'https://github.com/$releasesRepo/releases/download/v$version/$name';
  return {
    'tag_name': 'v$version',
    'html_url': 'https://github.com/$releasesRepo/releases/tag/v$version',
    'draft': false,
    'prerelease': prerelease,
    'body': "## What's new in $version\n\n- **Volume** everywhere.\n- Check for `updates`.\n\n---\n\n# User guide\n...",
    'assets': [
      for (final n in [
        'HomeTunes-$version-android.apk',
        'HomeTunes-Setup-$version.exe',
        'HomeTunes-$version-windows.zip',
        'HomeTunes-$version-SHA256SUMS.txt',
      ])
        {'name': n, 'browser_download_url': dl(n)},
    ],
  };
}

void main() {
  group('Versions', () {
    test('newer only when a number is higher', () {
      expect(isNewerVersion('0.1.23', '0.1.22'), isTrue);
      expect(isNewerVersion('0.1.10', '0.1.9'), isTrue); // numbers, not text
      expect(isNewerVersion('0.2.0', '0.1.99'), isTrue);
      expect(isNewerVersion('1.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.1.22', '0.1.22'), isFalse);
      expect(isNewerVersion('0.1.21', '0.1.22'), isFalse);
      expect(isNewerVersion('0.1.22+30', '0.1.22'), isFalse); // the build number doesn't count
      expect(isNewerVersion('0.1.22.0', '0.1.22'), isFalse);
    });

    test('anything unreadable is never offered', () {
      expect(isNewerVersion('latest', '0.1.22'), isFalse);
      expect(isNewerVersion('0.1.23', ''), isFalse);
      expect(parseVersion('0.1.x'), isNull);
    });
  });

  group('Release page', () {
    test('reads the version, links and what\'s new', () {
      final r = ReleaseInfo.fromJson(releaseJson('0.1.23'))!;
      expect(r.version, '0.1.23');
      expect(r.installerName, 'HomeTunes-Setup-0.1.23.exe');
      expect(r.assets.keys, contains(r.checksumsName));
      expect(r.whatsNew, '- Volume everywhere.\n- Check for updates.');
      expect(r.page.path, '/$releasesRepo/releases/tag/v0.1.23');
    });

    test('pre-releases, drafts and odd tags are ignored', () {
      expect(ReleaseInfo.fromJson(releaseJson('0.1.23', prerelease: true)), isNull);
      expect(ReleaseInfo.fromJson({...releaseJson('0.1.23'), 'draft': true}), isNull);
      expect(ReleaseInfo.fromJson({...releaseJson('0.1.23'), 'tag_name': 'nightly'}), isNull);
      expect(ReleaseInfo.fromJson('nope'), isNull);
    });

    test('no what\'s new section gives empty text', () {
      expect(whatsNewFrom('# User guide\n\nStuff'), '');
    });

    test('checksum file', () {
      final a = 'a' * 64, b = 'B' * 64;
      final sums = parseChecksums('$a  HomeTunes-Setup-0.1.23.exe\r\n$b *HomeTunes-0.1.23-android.apk\nrubbish\n');
      expect(sums, {'HomeTunes-Setup-0.1.23.exe': a, 'HomeTunes-0.1.23-android.apk': 'b' * 64});
    });

    test('only this project\'s release downloads are fetched', () {
      expect(isReleaseDownload(Uri.parse('https://github.com/$releasesRepo/releases/download/v1/x.exe')), isTrue);
      expect(isReleaseDownload(Uri.parse('http://github.com/$releasesRepo/releases/download/v1/x.exe')), isFalse);
      expect(isReleaseDownload(Uri.parse('https://github.com/someone/else/releases/download/v1/x.exe')), isFalse);
      expect(isReleaseDownload(Uri.parse('https://example.com/$releasesRepo/releases/download/v1/x.exe')), isFalse);
    });
  });

  group('UpdateModel', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_update'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    UpdateModel model(String latest, {String current = '0.1.22', int status = 200}) => UpdateModel(
          Storage.at(dir),
          readVersion: () async => current,
          checker: UpdateChecker(
            client: MockClient((req) async => http.Response(jsonEncode(releaseJson(latest)), status)),
          ),
        );

    test('finds a newer version and remembers when it looked', () async {
      final u = model('0.1.23');
      await u.load();
      expect(u.isDue, isTrue); // never checked
      final found = await u.check();
      expect(found?.version, '0.1.23');
      expect(u.stage, UpdateStage.available);
      expect(u.isDue, isFalse); // just checked

      final again = model('0.1.23');
      await again.load();
      expect(again.lastCheck, isNotNull);
      again.now = () => DateTime.now().add(const Duration(hours: 25));
      expect(again.isDue, isTrue); // a day later
    });

    test('says up to date when there\'s nothing newer', () async {
      final u = model('0.1.22');
      await u.load();
      expect(await u.check(), isNull);
      expect(u.stage, UpdateStage.upToDate);
    });

    test('a failed check shows a message, but the quiet one stays quiet', () async {
      final u = model('0.1.23', status: 500);
      await u.load();
      expect(await u.check(quiet: true), isNull);
      expect(u.stage, UpdateStage.idle);
      await u.check();
      expect(u.stage, UpdateStage.failed);
      expect(u.error, contains('500'));
    });

    test('turning the daily check off is remembered', () async {
      final u = model('0.1.23');
      await u.load();
      await u.setAutoCheck(false);
      expect(u.isDue, isFalse);
      expect(await u.checkIfDue(), isNull);
      final again = model('0.1.23');
      await again.load();
      expect(again.autoCheck, isFalse);
    });
  });

  group('Downloading the installer', () {
    final installer = utf8.encode('pretend installer bytes');
    final release = ReleaseInfo.fromJson(releaseJson('0.1.23'))!;

    UpdateChecker checker(String sum) => UpdateChecker(
          client: MockClient((req) async {
            if (req.url.path.endsWith('SHA256SUMS.txt')) {
              return http.Response('$sum  HomeTunes-Setup-0.1.23.exe\n', 200);
            }
            if (req.url.path.endsWith('.exe')) return http.Response.bytes(installer, 200);
            return http.Response('', 404);
          }),
        );

    test('keeps the file when the checksum matches', () async {
      final progress = <double?>[];
      final file = await checker(sha256.convert(installer).toString())
          .downloadInstaller(release, onProgress: progress.add);
      expect(await file.readAsBytes(), installer);
      expect(progress.last, anyOf(1.0, isNull));
      await file.delete();
    });

    test('refuses and deletes a file whose checksum doesn\'t match', () async {
      await expectLater(checker('0' * 64).downloadInstaller(release), throwsA(isA<UpdateException>()));
      final left = File('${Directory.systemTemp.path}/HomeTunes-update/HomeTunes-Setup-0.1.23.exe');
      expect(left.existsSync(), isFalse);
    });
  });

  test('"last checked" wording', () {
    final now = DateTime(2026, 10, 3, 18);
    expect(lastCheckedText(DateTime(2026, 10, 3, 9, 5), now), 'Last checked today at 09:05');
    expect(lastCheckedText(DateTime(2026, 10, 2, 22, 30), now), 'Last checked yesterday at 22:30');
    expect(lastCheckedText(DateTime(2026, 9, 28, 12), now), 'Last checked on 28 Sep');
  });
}
