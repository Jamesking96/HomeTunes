// 0.2.8: typing on the TV. Predicted words over the keyboard (services/word_predictor.dart), and
// the keyboard fitting where it's used (ui/tv/tv_words.dart): capitals, the number pad, and no
// predictions or memory for a password.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/word_predictor.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_keyboard.dart';
import 'package:hometunes/ui/tv/tv_words.dart';
import 'package:provider/provider.dart';

List<String> words(List<Prediction> list) => [for (final p in list) p.word];

void main() {
  group('predicted words', () {
    final names = [
      'The Lion King',
      'The Lion King 1½',
      'The Lion King II: Simba\'s Pride',
      'The Little Mermaid',
      'Lilo & Stitch',
      'Linkin Park',
      'The Simpsons',
      'Lion',
    ];

    test('the words starting with what\'s typed, the commonest first, four at most', () {
      final w = WordPredictor(names: names);
      expect(words(w.predict('li')).first, 'Lion');
      expect(words(w.predict('li')), containsAll(['Lion', 'Little', 'Lilo', 'Linkin']));
      expect(w.predict('li'), hasLength(4));
      expect(words(w.predict('lio')), ['Lion']);
      // Its own spelling; a capital when the typing started with one.
      expect(words(WordPredictor(names: ['iPhone stories']).predict('iph')), ['iPhone']);
      expect(words(WordPredictor(names: ['the end']).predict('Th')), ['The']);
    });

    test('the word before counts: "lion" then k… is king; after a space, what comes next', () {
      final w = WordPredictor(names: [...names, 'Kingdom Hearts', 'Kingdom Hearts II', 'Kingdom Come']);
      expect(words(w.predict('the lion k')).first, 'King');
      expect(words(w.predict('k')), containsAll(['King', 'Kingdom']));
      expect(words(w.predict('the lion ')), ['King']);
      expect(words(w.predict('the ')), containsAll(['Lion', 'Little', 'Simpsons']));
      expect(words(w.predict('the ')).first, 'Lion');
      expect(w.predict(''), isEmpty);
    });

    test('a slip: nothing starts "lino", so the words one slip away', () {
      final w = WordPredictor(names: names);
      expect(words(w.predict('lino')), contains('Lion'));
      expect(words(w.predict('simsp')), contains('Simpsons'));
      expect(w.predict('zzzz'), isEmpty);
    });

    test('putting a word in: the word being typed becomes it, then a space', () {
      expect(WordPredictor.apply('the li', const Prediction('lion')), 'the lion ');
      expect(WordPredictor.apply('the ', const Prediction('lion')), 'the lion ');
      expect(WordPredictor.apply('', const Prediction('lion')), 'lion ');
      expect(WordPredictor.apply('sci', const Prediction('Science Fiction', whole: true)), 'Science Fiction');
    });

    test('Search: small letters; a Genre box: whole genres too', () {
      final s = WordPredictor(names: names, lowerCase: true);
      expect(words(s.predict('li')).first, 'lion');
      final g = WordPredictor(names: ['Science Fiction', 'Science Fiction', 'Comedy', 'Sitcom'], phrases: ['Science Fiction', 'Comedy', 'Sitcom']);
      final p = g.predict('sc');
      expect(p.first, const Prediction('Science Fiction', whole: true));
      expect(words(g.predict('')), ['Comedy', 'Sitcom', 'Science Fiction']);
      // A genre that's one word is offered once, as the genre.
      final one = WordPredictor(names: ['Action', 'Adventure'], phrases: ['Action', 'Adventure']).predict('A');
      expect(one, [const Prediction('Action', whole: true), const Prediction('Adventure', whole: true)]);
    });

    test('words typed before are offered, and count more', () {
      final w = WordPredictor(names: ['Hollow Knight'], learned: {'Holiday': 2});
      expect(words(w.predict('ho')).first, 'Holiday');
      expect(WordPredictor.wordsIn('A trip, (1994) to the sea.'), ['trip', 'to', 'the', 'sea']);
    });
  });

  test('what a box is for, from its label and keyboard', () {
    expect(tvTypingFor(label: 'Password', obscure: true), TvTyping.secret);
    expect(tvTypingFor(label: 'Password'), TvTyping.secret); // shown, still a password
    expect(tvTypingFor(label: 'Year', keyboardType: TextInputType.number), TvTyping.number);
    expect(tvTypingFor(label: 'Season', keyboardType: const TextInputType.numberWithOptions(decimal: true)), TvTyping.number);
    expect(tvTypingFor(label: 'Server address', keyboardType: TextInputType.url), TvTyping.address);
    expect(tvTypingFor(label: 'Username'), TvTyping.plain);
    expect(tvTypingFor(label: 'Genre'), TvTyping.pick);
    expect(tvTypingFor(label: 'Search artist'), TvTyping.pick);
    expect(tvTypingFor(label: 'Title'), TvTyping.title);
    expect(tvTypingFor(label: 'Description', multiline: true), TvTyping.sentence);
    expect(tvTypingFor(label: 'Colour code'), TvTyping.secret);
    expect(TvTyping.secret.predicts, isFalse);
    expect(TvTyping.address.remembers, isFalse);
  });

  group('the TV keyboard', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_tv_typing');
      storage = Storage.at(dir);
      Directory(storage.artDir).createSync(recursive: true);
      lib = LibraryModel(storage);
      TypedWords.forget();
    });
    tearDown(() async {
      TypedWords.forget();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<Future<String?>> open(WidgetTester tester, String title, {TvTyping? typing, bool obscure = false}) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      late BuildContext ctx;
      await tester.pumpWidget(MultiProvider(
        providers: libraryProviders(lib),
        child: MaterialApp(
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: Builder(builder: (context) {
            ctx = context;
            return const Scaffold();
          }),
        ),
      ));
      final result = showTvTextInput(ctx, title: title, typing: typing, obscure: obscure);
      await tester.pumpAndSettle();
      return result;
    }

    String typed(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('tv-text'))).data!;
    Future<void> key(WidgetTester tester, String k) async {
      await tester.tap(find.byKey(ValueKey(k)));
      await tester.pumpAndSettle();
    }

    testWidgets('a title: a capital at the start of each word by itself; Shift makes one small', (tester) async {
      await tester.runAsync(() => TypedWords.load(lib));
      final done = await open(tester, 'Title');
      expect(find.byKey(const ValueKey('tv-predictions')), findsOneWidget);
      for (final k in ['t', 'h', 'e', 'Space', 'e', 'n', 'd']) {
        await key(tester, 'tv-key-$k');
      }
      expect(typed(tester), 'The End|');
      await key(tester, 'tv-key-Space');
      await key(tester, 'tv-key-Shift'); // this one small
      await key(tester, 'tv-key-o');
      await key(tester, 'tv-key-f');
      expect(typed(tester), 'The End of|');
      await key(tester, 'tv-key-Done');
      expect(await done, 'The End of');
      // Remembered for next time (a title box remembers).
      final learned = await tester.runAsync(() => TypedWords.load(lib));
      expect(learned!.keys, containsAll(['The', 'End', 'of']));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    });

    testWidgets('a number box opens on the number pad', (tester) async {
      final done = await open(tester, 'Year', typing: TvTyping.number);
      expect(find.byKey(const ValueKey('tv-num-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-key-a')), findsNothing);
      expect(find.byKey(const ValueKey('tv-predictions')), findsNothing);
      for (final k in ['1', '9', '9', '4']) {
        await key(tester, 'tv-num-$k');
      }
      await key(tester, 'tv-key-Done');
      expect(await done, '1994');
    });

    testWidgets('a password: no predictions, nothing remembered', (tester) async {
      final done = await open(tester, 'Password', obscure: true);
      expect(find.byKey(const ValueKey('tv-predictions')), findsNothing);
      await key(tester, 'tv-key-a');
      expect(typed(tester), '•|');
      await key(tester, 'tv-key-Done');
      expect(await done, 'a');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      expect(File('${dir.path}/${TypedWords.file}').existsSync(), isFalse);
    });

    testWidgets('a prediction: OK puts it in (a word typed before, with a capital to start a sentence)', (tester) async {
      await tester.runAsync(() => TypedWords.learn(lib, 'wonderful wonderful'));
      final done = await open(tester, 'Description', typing: TvTyping.sentence);
      await key(tester, 'tv-key-w');
      expect(typed(tester), 'W|');
      expect(find.descendant(of: find.byKey(const ValueKey('tv-predict-0')), matching: find.text('Wonderful')), findsOneWidget);
      await key(tester, 'tv-predict-0');
      expect(typed(tester), 'Wonderful |');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await done, isNull);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    });
  });
}
