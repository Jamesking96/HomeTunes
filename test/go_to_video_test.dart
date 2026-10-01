// 1 Oct: "Go to the video" on the bottom bar, pressed while already on the Videos tab, closed the
// video page (selectTab goes back to the tab's first page) and then emptied the tab while looking
// for it, leaving a blank Videos tab until a restart. showTab only switches tabs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/nav.dart';

void main() {
  testWidgets('showTab keeps the tab\'s pages; going back to a page never empties the tab', (tester) async {
    final nav = AppNav()..tab = AppNav.videosTab;
    await tester.pumpWidget(MaterialApp(
      home: Navigator(
        key: nav.keys[AppNav.videosTab],
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Text('Videos home')),
      ),
    ));
    late Route<void> videoPage;
    nav.push(Builder(builder: (context) {
      videoPage = ModalRoute.of(context)! as Route<void>;
      return const Text('Video page');
    }));
    await tester.pumpAndSettle();
    nav.push(const Text('Collection page'));
    await tester.pumpAndSettle();

    // Already on the Videos tab: nothing is closed.
    nav.showTab(AppNav.videosTab);
    await tester.pumpAndSettle();
    expect(find.text('Collection page'), findsOneWidget);

    // Back to the video page: only the pages above it close.
    nav.current!.popUntil((r) => r == videoPage || r.isFirst);
    await tester.pumpAndSettle();
    expect(find.text('Video page'), findsOneWidget);

    // A page that's gone: the tab's first page stays (before, the tab was left empty).
    nav.current!.pop();
    await tester.pumpAndSettle();
    expect(videoPage.isActive, isFalse);
    nav.current!.popUntil((r) => r == videoPage || r.isFirst);
    await tester.pumpAndSettle();
    expect(find.text('Videos home'), findsOneWidget);

    // Switching from another tab still works.
    nav.tab = 0;
    nav.showTab(AppNav.videosTab);
    expect(nav.tab, AppNav.videosTab);
  });
}
