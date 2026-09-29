// Tests for "What's new" after an update (0.1.28): which releases are listed, how UpdateModel
// notices the first start after an update (and doesn't on a fresh install), and the pop-up
// showing each version's notes with bullets and bold. GitHub is a fake http client.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/update_checker.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/ui/screens/settings/whats_new_ui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> release(String version, {String? notes, bool prerelease = false}) => {
      'tag_name': 'v$version',
      'html_url': 'https://github.com/$releasesRepo/releases/tag/v$version',
      'draft': false,
      'prerelease': prerelease,
      'body': notes == null
          ? '# User guide\n...'
          : "## What's new in $version\n\n$notes\n\n---\n\n# User guide\n...",
      'assets': <Object>[],
    };

ReleaseInfo info(String version, {String notes = '- Something.'}) =>
    ReleaseInfo.fromJson(release(version, notes: notes))!;

void main() {
  group('Which releases are listed', () {
    final all = [
      info('0.1.29'),
      info('0.1.28'),
      info('0.1.27'),
      ReleaseInfo.fromJson(release('0.1.26'))!, // no "What's new"
      info('0.1.25'),
      info('0.1.24'),
    ];

    test('everything after the old version, up to this one, newest first', () {
      final list = releasesSince(all.reversed, from: '0.1.24', to: '0.1.28');
      expect(list.map((r) => r.version), ['0.1.28', '0.1.27', '0.1.25']);
    });

    test('old version not known: just this version', () {
      expect(releasesSince(all, to: '0.1.27').map((r) => r.version), ['0.1.27']);
    });

    test('a build that was never published has nothing', () {
      expect(releasesSince(all, to: '0.1.30', from: '0.1.29'), isEmpty);
    });

    test('the notes keep their bullets and bold', () {
      final r = info('0.1.28', notes: '- **Bold** thing.\n  - sub point');
      expect(r.notes, '- **Bold** thing.\n  - sub point');
      expect(r.whatsNew, '- Bold thing.\n  - sub point');
    });
  });

  group('Noticing an update', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_whatsnew'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    UpdateModel model(String current) => UpdateModel(
          Storage.at(dir),
          readVersion: () async => current,
          checker: UpdateChecker(
            client: MockClient((req) async {
              if (req.url.path.endsWith('/releases')) {
                return http.Response(jsonEncode([for (final v in ['0.1.28', '0.1.27', '0.1.25', '0.1.24'])
                  release(v, notes: '- Changes in $v.')]), 200);
              }
              return http.Response('', 404);
            }),
          ),
        );
    void writeUpdates(Map<String, Object> json) => File('${dir.path}/updates.json').writeAsStringSync(jsonEncode(json));

    test('a brand-new install shows nothing, and remembers its version', () async {
      final u = model('0.1.28');
      await u.load();
      expect(u.justUpdated, isFalse);
      expect(u.lastRunVersion, '0.1.28');
      final again = model('0.1.28');
      await again.load();
      expect(again.justUpdated, isFalse);
    });

    test('after updating, lists every version since the old one, then not again', () async {
      writeUpdates({'autoCheck': true, 'lastRunVersion': '0.1.24'});
      final u = model('0.1.28');
      await u.load();
      expect(u.justUpdated, isTrue);
      expect(u.updatedFrom, '0.1.24');
      final list = await u.fetchWhatsNew();
      expect(list.map((r) => r.version), ['0.1.28', '0.1.27', '0.1.25']);
      expect(list.first.notes, '- Changes in 0.1.28.');
      await u.markWhatsNewSeen();

      final next = model('0.1.28');
      await next.load();
      expect(next.justUpdated, isFalse);
    });

    test('updating from a version that didn\'t record itself shows this version\'s notes', () async {
      writeUpdates({'autoCheck': true}); // written by 0.1.23–0.1.27
      final u = model('0.1.27');
      await u.load();
      expect(u.justUpdated, isTrue);
      expect(u.updatedFrom, isNull);
      expect((await u.fetchWhatsNew()).map((r) => r.version), ['0.1.27']);
    });

    test('a library from before 0.1.23 (no updates.json) also counts as an update', () async {
      File('${dir.path}/settings.json').writeAsStringSync('{}');
      final u = model('0.1.28');
      await u.load();
      expect(u.justUpdated, isTrue);
    });

    test('going back to an older version shows nothing', () async {
      writeUpdates({'lastRunVersion': '0.1.28'});
      final u = model('0.1.27');
      await u.load();
      expect(u.justUpdated, isFalse);
      expect(u.lastRunVersion, '0.1.27');
    });

    test('offline: the list can\'t be fetched, and says why', () async {
      writeUpdates({'lastRunVersion': '0.1.24'});
      final u = UpdateModel(Storage.at(dir),
          readVersion: () async => '0.1.28',
          checker: UpdateChecker(client: MockClient((_) async => throw const SocketException('offline'))));
      await u.load();
      expect(u.justUpdated, isTrue);
      await expectLater(u.fetchWhatsNew(), throwsA(isA<UpdateException>()));
    });
  });

  group('The pop-up', () {
    Future<void> show(WidgetTester tester, Widget dialog) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: dialog))));
      await tester.pump();
    }

    testWidgets('lists each version with its notes', (tester) async {
      await show(
        tester,
        WhatsNewDialog(
          version: '0.1.28',
          from: '0.1.24',
          afterUpdate: true,
          releases: [
            info('0.1.28', notes: '- **What\'s new pop-up.** Shows after an update.\n  - Also in Settings.'),
            info('0.1.27', notes: '- Folder options.'),
          ],
        ),
      );
      expect(find.text('HomeTunes has been updated from 0.1.24 to 0.1.28.'), findsOneWidget);
      expect(find.byKey(const Key('whats-new-version:0.1.28')), findsOneWidget);
      expect(find.byKey(const Key('whats-new-version:0.1.27')), findsOneWidget);
      expect(find.text('Folder options.', findRichText: true), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('◦'), findsOneWidget); // the indented point
      expect(find.byKey(const Key('whats-new-problem')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offline: still says the version, and why there\'s no list', (tester) async {
      await show(
        tester,
        const WhatsNewDialog(version: '0.1.28', afterUpdate: true, releases: [], problem: 'No internet.'),
      );
      expect(find.text('HomeTunes has been updated to 0.1.28.'), findsOneWidget);
      expect(find.byKey(const Key('whats-new-problem')), findsOneWidget);
      expect(find.text('Open release page'), findsOneWidget);
    });
  });

  test('bold, code and links in a line', () {
    final span = inlineSpans('Go to **Settings > About**, run `x` or see [the guide](https://x.y).', const TextStyle());
    final pieces = span.children!.cast<TextSpan>();
    expect(pieces.map((s) => s.text).join(), 'Go to Settings > About, run x or see the guide.');
    final bold = pieces.where((s) => s.style?.fontWeight == FontWeight.w700).map((s) => s.text);
    expect(bold, ['Settings > About']);
    // An unpaired ** isn't turned into bold.
    final odd = inlineSpans('a **b', const TextStyle()).children!.cast<TextSpan>();
    expect(odd.where((s) => s.style?.fontWeight == FontWeight.w700), isEmpty);
  });
}
