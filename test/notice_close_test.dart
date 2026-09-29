// Tests for 0.1.30: every notice at the bottom of the screen has a ✕ to close it at once,
// beside Undo (or whatever button it has), in the ready-made, light and dark themes. Closing it
// doesn't do the Undo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/screens/settings/appearance_settings.dart';
import 'package:hometunes/ui/theme.dart';

void main() {
  for (final palette in [defaultPalette, ...builtInPalettes.skip(1), lightStarter]) {
    testWidgets('a notice can be closed with ✕ (${palette.name})', (tester) async {
      var undone = false;
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(palette, 1),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Moved to Books'),
                duration: const Duration(minutes: 1), // would otherwise stay up for a minute
                action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
              )),
              child: const Text('show'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(find.text('Moved to Books'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      final close = find.descendant(of: find.byType(SnackBar), matching: find.byIcon(Icons.close));
      expect(close, findsOneWidget);

      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Moved to Books'), findsNothing);
      expect(undone, isFalse);
    });
  }
}
