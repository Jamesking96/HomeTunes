// Draws Profiles (0.2.13, phase 1) off-screen and saves pictures to C:\Temp\ht\preview (nothing
// is shown on screen): "Who's listening?" on a PC window and a phone, Settings › Profiles with
// profiles on, and the add-a-profile dialog. Uses Windows' Segoe UI so the text is readable.
//   flutter test tool/profiles_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/profiles_model.dart';
import 'package:hometunes/ui/profiles/profile_ui.dart';
import 'package:hometunes/ui/profiles/whos_listening.dart';
import 'package:hometunes/ui/screens/settings/profile_settings.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_profiles_preview'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<ProfilesModel> family(WidgetTester tester) async {
    final m = ProfilesModel(Storage.at(dir));
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
      await Storage.at(dir).write(ProfilesModel.fileName, {
        'on': true,
        'profiles': [
          {'id': 'p1', 'name': 'James', 'colour': '#FF7A59', 'icon': 'headphones'},
          {'id': 'p2', 'name': 'Sarah', 'colour': '#4FC3F7', 'icon': 'book'},
          {'id': 'p3', 'name': 'Kids', 'colour': '#81C784', 'icon': 'star'},
        ],
        'last': 'p1',
      });
      await m.load();
    });
    return m;
  }

  Future<void> draw(WidgetTester tester, ProfilesModel m, Size size, String name, Widget home,
      {Future<void> Function()? then}) async {
    Directory(out).createSync(recursive: true);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: ChangeNotifierProvider<ProfilesModel?>.value(
        value: m,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home),
      ),
    ));
    await tester.pumpAndSettle();
    if (then != null) {
      await then();
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  testWidgets('Who\'s listening? on a PC', (tester) async {
    final m = await family(tester);
    await draw(tester, m, const Size(1280, 800), 'profiles-whos-listening', const WhosListeningScreen());
  });

  testWidgets('Who\'s listening? on a phone', (tester) async {
    final m = await family(tester);
    await draw(tester, m, const Size(412, 860), 'profiles-whos-listening-phone', const WhosListeningScreen());
  });

  testWidgets('Settings › Profiles', (tester) async {
    final m = await family(tester);
    await draw(tester, m, const Size(900, 700), 'profiles-settings',
        Scaffold(appBar: AppBar(title: const Text('Profiles'), actions: const [ProfileButton()]), body: const ProfileSettings()));
  });

  testWidgets('Add a profile', (tester) async {
    final m = await family(tester);
    await draw(tester, m, const Size(900, 760), 'profiles-add',
        const Scaffold(body: ProfileSettings()),
        then: () => tester.tap(find.text('Add a profile')));
  });
}
