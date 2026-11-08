// Profiles, phase 1 on screen: "Who's listening?" at the start (ui/profiles/whos_listening.dart),
// the profile button and Settings › Profiles (ui/screens/settings/profile_settings.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_rail.dart';
import 'package:hometunes/ui/tv/tv_widgets.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/profiles_model.dart';
import 'package:hometunes/ui/profiles/profile_ui.dart';
import 'package:hometunes/ui/profiles/whos_listening.dart';
import 'package:hometunes/ui/screens/settings/profile_settings.dart';
import 'package:hometunes/ui/screens/settings/update_ui.dart' show appNavigatorKey;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_whos');
    storage = Storage.at(dir);
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ProfilesModel> twoProfiles(WidgetTester tester) async {
    final m = ProfilesModel(storage);
    await tester.runAsync(() async {
      await storage.write(ProfilesModel.fileName, {
        'on': true,
        'profiles': [
          {'id': 'p1', 'name': 'Sam', 'colour': '#FF7A59', 'icon': 'headphones'},
          {'id': 'p2', 'name': 'Alex', 'colour': '#4FC3F7', 'icon': 'star'},
        ],
        'last': 'p2',
      });
      await m.load();
    });
    return m;
  }

  Widget app(ProfilesModel? m, Widget child) => ChangeNotifierProvider<ProfilesModel?>.value(
        value: m,
        child: MaterialApp(navigatorKey: appNavigatorKey, home: child),
      );

  testWidgets('with profiles on it asks who\'s listening first; picking shows the app', (tester) async {
    final m = await twoProfiles(tester);
    expect(m.needsChoosing, isTrue);
    await tester.pumpWidget(app(m, const WhosListeningGate(child: Text('The app'))));
    expect(find.text('Who\'s listening?'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('The app'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Sam'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(m.currentId, 'p1');
    expect(find.text('The app'), findsOneWidget);
    expect(find.text('Who\'s listening?'), findsNothing);
  });

  testWidgets('with profiles off the app shows straight away', (tester) async {
    final m = ProfilesModel(storage);
    await tester.runAsync(m.load);
    await tester.pumpWidget(app(m, const WhosListeningGate(child: Text('The app'))));
    expect(find.text('The app'), findsOneWidget);
    // And without profiles at all (tests, previews).
    await tester.pumpWidget(app(null, const WhosListeningGate(child: Text('The app'))));
    expect(find.text('The app'), findsOneWidget);
  });

  testWidgets('the profile button shows whose things these are, and nothing when off', (tester) async {
    final m = await twoProfiles(tester);
    await tester.pumpWidget(app(m, const Scaffold(body: Center(child: ProfileButton()))));
    expect(find.byTooltip('Alex · Switch profile'), findsOneWidget);
    await tester.tap(find.byType(ProfileButton));
    await tester.pumpAndSettle();
    expect(find.text('Who\'s listening?'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    final off = ProfilesModel(storage.forProfile('p9'));
    await tester.pumpWidget(app(off, const Scaffold(body: Center(child: ProfileButton()))));
    expect(find.byType(Tooltip), findsNothing);
  });

  // Phase 2: the TV.
  Widget tvApp(ProfilesModel m, Widget child) => ChangeNotifierProvider<ProfilesModel?>.value(
        value: m,
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          builder: (context, page) => TvFocus(enabled: true, sounds: false, child: page!),
          home: child,
        ),
      );

  testWidgets('on the TV, Who\'s listening? starts on the last one and OK picks it', (tester) async {
    final m = await twoProfiles(tester);
    await tester.pumpWidget(tvApp(m, const WhosListeningGate(child: Text('The app'))));
    await tester.pump();
    expect(find.byType(TvPressable), findsNWidgets(2));
    // Alex (the last one) has the remote.
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvPressable>(), isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(m.needsChoosing, isFalse);
    expect(m.currentId, 'p2');
    expect(find.text('The app'), findsOneWidget);
  });

  testWidgets('on the TV, the switcher is the options panel with the one in use', (tester) async {
    final m = await twoProfiles(tester);
    await tester.pumpWidget(tvApp(m, const Scaffold(body: Center(child: ProfileButton()))));
    await tester.tap(find.byType(ProfileButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-option-Sam')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-option-Alex')), findsOneWidget);
    expect(find.text('Using now'), findsOneWidget);
  });

  testWidgets('the TV menu shows whose things these are when profiles are on', (tester) async {
    var pressed = 0;
    Widget rail({Widget? profile}) => MaterialApp(
          home: Scaffold(
            body: TvRail(
              items: const [TvRailItem('Home', Icons.home)],
              selected: 0,
              onSelect: (_) {},
              profile: profile,
              profileLabel: 'Sam · Switch profile',
              onProfile: () => pressed++,
            ),
          ),
        );
    await tester.pumpWidget(rail());
    expect(find.byKey(const ValueKey('tv-rail-profile')), findsNothing);
    await tester.pumpWidget(rail(profile: const SizedBox()));
    await tester.tap(find.byKey(const ValueKey('tv-rail-profile')));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('Settings › Profiles: off at first; on lists everyone with Add a profile', (tester) async {
    final off = ProfilesModel(storage);
    await tester.runAsync(off.load);
    await tester.pumpWidget(app(off, const Scaffold(body: ProfileSettings())));
    expect(find.text('Use profiles'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect(find.text('Add a profile'), findsNothing);

    final m = await twoProfiles(tester);
    await tester.pumpWidget(app(m, const Scaffold(body: ProfileSettings())));
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Using now'), findsOneWidget);
    expect(find.text('Add a profile'), findsOneWidget);
    // The one in use can't be removed.
    expect(find.byTooltip('Remove'), findsOneWidget);
  });
}
