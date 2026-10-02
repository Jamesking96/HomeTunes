// 0.1.50: the internet check at start-up and before online features (InternetCheck,
// offline_warning.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/internet_check.dart';
import 'package:hometunes/ui/widgets/offline_warning.dart';

void main() {
  var online = false;
  var checks = 0;
  setUp(() {
    online = false;
    checks = 0;
    InternetCheck.override = () async {
      checks++;
      return online;
    };
  });
  tearDown(() => InternetCheck.override = null);

  Future<GlobalKey<NavigatorState>> pumpApp(WidgetTester tester, {VoidCallback? onFeature}) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              if (await ensureOnline(context)) onFeature?.call();
            },
            child: const Text('Find online'),
          ),
        ),
      ),
    ));
    return key;
  }

  testWidgets('at start-up: a warning with Carry on when offline, nothing when online', (tester) async {
    final key = await pumpApp(tester);
    final done = checkInternetAtStart(key);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('offline-warning')), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    for (final f in onlineFeatures) {
      expect(find.text(f), findsOneWidget);
    }
    expect(find.text('Try anyway'), findsNothing);
    await tester.tap(find.text('Carry on'));
    await tester.pumpAndSettle();
    await done;
    expect(find.byKey(const ValueKey('offline-warning')), findsNothing);
    expect(find.text('Find online'), findsOneWidget); // the app carries on

    online = true;
    await checkInternetAtStart(key);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('offline-warning')), findsNothing);
  });

  testWidgets('an online feature checks again each time', (tester) async {
    var ran = 0;
    await pumpApp(tester, onFeature: () => ran++);

    // Still offline: the same warning; OK doesn't go ahead.
    await tester.tap(find.text('Find online'));
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(find.text('No internet connection'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(ran, 0);

    // Again: checked again, warned again; Try anyway goes ahead.
    await tester.tap(find.text('Find online'));
    await tester.pumpAndSettle();
    expect(checks, 2);
    await tester.tap(find.text('Try anyway'));
    await tester.pumpAndSettle();
    expect(ran, 1);

    // Back online: no warning, straight through.
    online = true;
    await tester.tap(find.text('Find online'));
    await tester.pumpAndSettle();
    expect(checks, 3);
    expect(find.text('No internet connection'), findsNothing);
    expect(ran, 2);
    expect(InternetCheck.last, isTrue);
  });
}
