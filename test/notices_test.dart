// 1 Oct: every notice lives 15 seconds from when it's raised, shown or still waiting; notices
// with a button no longer stay for ever; the same words aren't queued twice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/widgets/notices.dart';

void main() {
  final key = GlobalKey<ScaffoldMessengerState>();

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        builder: (context, child) => NoticeMessenger(key: key, child: child!),
        home: const Scaffold(body: SizedBox()),
      ));

  SnackBar undo(String text) => SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      );

  testWidgets('a notice with a button closes after 15 seconds instead of staying', (tester) async {
    await pumpApp(tester);
    key.currentState!.showSnackBar(undo('Removed from the queue'));
    await tester.pumpAndSettle();
    expect(find.text('Removed from the queue'), findsOneWidget);
    await tester.pump(const Duration(seconds: 14));
    expect(find.text('Removed from the queue'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Removed from the queue'), findsNothing);
  });

  testWidgets('notices waiting behind one run out of time too, so they don\'t pile up', (tester) async {
    await pumpApp(tester);
    final m = key.currentState! as NoticeMessengerState;
    m.showSnackBar(undo('First'));
    for (var i = 1; i <= 5; i++) {
      m.showSnackBar(undo('Waiting $i'));
    }
    m.showSnackBar(undo('Waiting 1')); // the same words again: not queued twice
    await tester.pumpAndSettle();
    expect(m.waitingCount, 5);

    // 10 s later a new one is raised; the first is closed by hand after 12 s.
    await tester.pump(const Duration(seconds: 10));
    m.showSnackBar(undo('Later'));
    await tester.pump(const Duration(seconds: 2));
    m.hideCurrentSnackBar();
    await tester.pumpAndSettle();
    // Waiting 1 shows with the 3 s it has left.
    expect(find.text('Waiting 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    // Waiting 2–5 ran out unseen; "Later" still had time.
    expect(find.text('Later'), findsOneWidget);
    expect(m.waitingCount, 0);
    for (var i = 2; i <= 5; i++) {
      expect(find.text('Waiting $i'), findsNothing);
    }
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a short notice keeps its own shorter time', (tester) async {
    await pumpApp(tester);
    key.currentState!.showSnackBar(const SnackBar(content: Text('Saved'), duration: Duration(seconds: 2)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
