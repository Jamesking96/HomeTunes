// Downloads opens over the tab that's showing (4 Nov 2026, the user: "pressing back should take
// me back to the original tab I was at before going to downloads"); it used to switch to the
// Library tab, so Back from it never went back to Settings › Servers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/downloads_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Back from Downloads goes back to the tab it was opened from', (tester) async {
    final nav = AppNav()..tab = AppNav.settingsTab;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: nav,
      child: MaterialApp(
        home: Navigator(
          key: nav.keys[AppNav.settingsTab],
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Servers settings'))),
        ),
      ),
    ));
    nav.openDownloads();
    await tester.pumpAndSettle();
    expect(nav.tab, AppNav.settingsTab);
    expect(find.byType(DownloadsScreen), findsOneWidget);

    // Opened again from the sidebar while it's showing: not a second copy.
    nav.openDownloads();
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadsScreen), findsNothing);
    expect(find.text('Servers settings'), findsOneWidget);
    expect(nav.tab, AppNav.settingsTab);
  });
}
