// 0.1.49: every "Show only" drop-down has a search box at the top of its list
// (SearchChoiceField, used by the Library, Books and Videos filter sheets).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/widgets/search_choice_field.dart';

void main() {
  test('choiceMatches: every word, any order, ignoring case', () {
    expect(choiceMatches('The Rolling Stones', 'stones roll'), isTrue);
    expect(choiceMatches('The Rolling Stones', 'ROLL'), isTrue);
    expect(choiceMatches('The Rolling Stones', ''), isTrue);
    expect(choiceMatches('The Rolling Stones', 'beatles'), isFalse);
  });

  testWidgets('typing narrows the list; tap, Enter, All and Esc', (tester) async {
    String? picked;
    final options = {
      for (final (i, name) in ['Rock', 'Pop', 'Folk Rock', 'Jazz', 'Blues', 'Soul', 'Punk Rock'].indexed)
        name: i + 1,
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(20),
            child: SearchChoiceField(
              key: const ValueKey('filter-Genre'),
              label: 'Genre',
              value: picked,
              options: options,
              onChanged: (v) => setState(() => picked = v),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('All'), findsOneWidget);

    // Open: the search box comes first, then All and every choice.
    await tester.tap(find.byKey(const ValueKey('filter-Genre')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-search-Genre')), findsOneWidget);
    expect(find.text('Jazz  (4)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('choice-search-Genre')), 'rock');
    await tester.pump();
    expect(find.text('Jazz  (4)'), findsNothing);
    expect(find.text('Rock  (1)'), findsOneWidget);
    expect(find.text('Folk Rock  (3)'), findsOneWidget);
    expect(find.text('Punk Rock  (7)'), findsOneWidget);
    await tester.tap(find.text('Punk Rock  (7)'));
    await tester.pumpAndSettle();
    expect(picked, 'Punk Rock');
    expect(find.text('Punk Rock  (7)'), findsOneWidget); // shown in the field

    // Enter picks the first match.
    await tester.tap(find.byKey(const ValueKey('filter-Genre')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('choice-search-Genre')), 'so');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, 'Soul');

    // Nothing matching says so.
    await tester.tap(find.byKey(const ValueKey('filter-Genre')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('choice-search-Genre')), 'zzz');
    await tester.pump();
    expect(find.text('Nothing matches'), findsOneWidget);
    // Esc closes it without changing anything.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-search-Genre')), findsNothing);
    expect(picked, 'Soul');

    // All clears the pick.
    await tester.tap(find.byKey(const ValueKey('filter-Genre')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('choice:(all)')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
