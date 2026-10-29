// Shuffle for video collections (0.2.6): the order (state/video_shuffle.dart), which seasons are
// in it (VideoLibraryModel, kept in videos.json), and the buttons on PC / phone and the TV.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_shuffle.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/video_collection_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_collection_page.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

VideoItem _v(String id, {int? season, bool extra = false}) =>
    VideoItem(id: id, path: '/v/$id.mkv', title: id, collection: 'Silo', season: season, episode: 1, extra: extra);

/// Notes what openVideo was asked to play, instead of opening a player.
class _Nav extends AppNav {
  VideoItem? opened;
  VideoShuffle? shuffle;
  @override
  void openVideo(VideoItem v, {VideoShuffle? shuffle}) {
    opened = v;
    this.shuffle = shuffle;
  }
}

void main() {
  test('a shuffle has each video once; after / before / where it is', () {
    final videos = [for (var i = 1; i <= 20; i++) _v('e$i', season: 1)];
    final s = VideoShuffle.of('Silo', videos, label: 'Season 1', random: Random(7));
    expect(s.order.toSet(), {for (final v in videos) v.id});
    expect(s.length, 20);
    expect(s.order, isNot([for (final v in videos) v.id])); // not the usual order
    expect(s.after(s.order[0]), s.order[1]);
    expect(s.before(s.order[1]), s.order[0]);
    expect(s.before(s.first), isNull);
    expect(s.after(s.order.last), isNull); // stops at the end
    expect(s.after('elsewhere'), isNull);
    expect(s.placeOf(s.order[2]), '3 of 20');
  });

  test('in by default: seasons, parts and loose episodes; not Specials, special seasons or Extras', () {
    expect(shuffledByDefault(null, [_v('a')]), isTrue);
    expect(shuffledByDefault('Season 1', [_v('a', season: 1)]), isTrue);
    expect(shuffledByDefault('Alicization', [_v('a')]), isTrue);
    expect(shuffledByDefault('Specials', [_v('a', season: 0)]), isFalse);
    expect(shuffledByDefault('Extras', [_v('a', extra: true)]), isFalse);
    final ova = VideoItem(id: 'o', path: '/v/o.mkv', title: 'o', collection: 'Silo', season: 3, specialTitle: 'OVA');
    expect(shuffledByDefault('OVA', [ova]), isFalse);
  });

  test('what a shuffle is called', () {
    ShuffleGroup g(String h, bool on, {int? season = 1, bool extra = false}) =>
        ShuffleGroup(heading: h, label: h, videos: [_v(h, season: season, extra: extra)], included: on);
    expect(shuffleLabel([g('Season 1', true), g('Season 2', true)]), 'Whole collection');
    expect(shuffleLabel([g('Season 1', true), g('Season 2', true), g('Extras', false, extra: true)]), 'All seasons');
    expect(shuffleLabel([g('Season 1', true), g('Season 2', false), g('Season 3', true)]), 'Seasons 1, 3');
    expect(shuffleLabel([g('Season 1', false), g('Season 2', true)]), 'Season 2');
    expect(shuffleLabel([g('Season 1', true), g('Alicization', true, season: null), g('Season 3', false)]),
        'Season 1, Alicization');
  });

  group('with a series on disk', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel model;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_video_shuffle');
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      model = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await model.settle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // Silo: Seasons 1–3 of 4 episodes, a Specials season and an extra.
    Future<void> scan() async {
      final show = p.join(dir.path, 'vids', 'TV', 'Silo');
      for (var s = 0; s <= 3; s++) {
        final season = Directory(p.join(show, s == 0 ? 'Specials' : 'Season $s'))..createSync(recursive: true);
        for (var e = 1; e <= (s == 0 ? 2 : 4); e++) {
          File(p.join(season.path, 'Silo S0${s}E0$e.mkv')).writeAsBytesSync([1]);
        }
      }
      File(p.join((Directory(p.join(show, 'Extras'))..createSync()).path, 'Behind the scenes.mkv')).writeAsBytesSync([1]);
      await lib.addVideoFolder(p.join(dir.path, 'vids'));
      await model.scan();
    }

    Set<String> seasonsIn(VideoShuffle s) => {for (final id in s.order) VideoCollection.groupOf(model.byId(id)!)};

    test('the whole collection: the seasons, not Specials or Extras; one season: just it', () async {
      await scan();
      final c = model.collectionNamed('Silo')!;
      expect([for (final g in model.shuffleGroups(c)) '${g.heading}:${g.included}'],
          ['Season 1:true', 'Season 2:true', 'Season 3:true', 'Specials:false', 'Extras:false']);
      final all = model.shuffleOf(c, random: Random(1))!;
      expect(all.length, 12);
      expect(seasonsIn(all), {'Season 1', 'Season 2', 'Season 3'});
      expect(all.label, 'All seasons');

      final two = model.shuffleOf(c, heading: 'Season 2', random: Random(1))!;
      expect(seasonsIn(two), {'Season 2'});
      expect(two.length, 4);
      expect(two.label, 'Season 2');
      // Even a season that's out of the whole collection's shuffle shuffles on its own.
      expect(seasonsIn(model.shuffleOf(c, heading: 'Specials')!), {'Specials'});
    });

    test('seasons put in and taken out are kept for the collection, through a restart and a rename', () async {
      await scan();
      var c = model.collectionNamed('Silo')!;
      await model.setInShuffle(c, 'Season 2', false);
      await model.setInShuffle(c, 'Specials', true);
      expect(seasonsIn(model.shuffleOf(c)!), {'Season 1', 'Season 3', 'Specials'});
      expect(model.shuffleOf(c)!.label, 'Season 1, Season 3, Specials');

      // Saved: a new model reading videos.json has the same choice.
      await model.settle();
      final again = VideoLibraryModel(storage, lib);
      await again.load();
      expect(seasonsIn(again.shuffleOf(again.collectionNamed('Silo')!)!), {'Season 1', 'Season 3', 'Specials'});

      // Renaming the collection keeps it.
      await model.editCollection(c, name: 'Silo (2023)');
      c = model.collectionNamed('Silo (2023)')!;
      expect([for (final g in model.shuffleGroups(c)) if (g.included) g.heading], ['Season 1', 'Season 3', 'Specials']);

      // Putting a season back to its usual choice forgets it; Back to the usual forgets all.
      await model.setInShuffle(c, 'Season 2', true);
      await model.resetShuffle(c);
      expect([for (final g in model.shuffleGroups(c)) if (g.included) g.heading], ['Season 1', 'Season 2', 'Season 3']);

      // Everything out: nothing to shuffle.
      for (final h in ['Season 1', 'Season 2', 'Season 3']) {
        await model.setInShuffle(c, h, false);
      }
      expect(model.shuffleOf(c), isNull);
    });

    Future<void> pumpPage(WidgetTester tester, _Nav nav, Widget page, {bool tv = false}) async {
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...libraryProviders(lib),
          ChangeNotifierProvider.value(value: model),
          ChangeNotifierProvider<AppNav>.value(value: nav),
        ],
        child: MaterialApp(
          theme: tv ? tvTheme(buildTheme(), AppColors.accent) : null,
          builder: tv ? (context, child) => TvFocus(enabled: true, child: child!) : null,
          home: tv ? Scaffold(body: page) : page,
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('PC and phone: Shuffle, a season\'s own Shuffle, and Seasons in the shuffle', (tester) async {
      await tester.runAsync(scan);
      final nav = _Nav();
      await pumpPage(tester, nav, const VideoCollectionScreen(name: 'Silo'));

      await tester.tap(find.byKey(const ValueKey('collection-shuffle')));
      await tester.pump();
      expect(nav.shuffle!.length, 12);
      expect(nav.opened!.id, nav.shuffle!.first); // starts at the shuffle's first video

      await tester.tap(find.byKey(const ValueKey('season-shuffle:Season 1')));
      await tester.pump();
      expect(seasonsIn(nav.shuffle!), {'Season 1'});

      // Take Season 1 out, put Specials in: the next Shuffle plays those.
      await tester.tap(find.byKey(const ValueKey('collection-shuffle-seasons')));
      await tester.pumpAndSettle();
      expect(find.text('Seasons in the shuffle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shuffle-season:Season 1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shuffle-season:Specials')));
      await tester.pumpAndSettle();
      expect(find.text('10 videos in the shuffle'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shuffle-now')));
      await tester.pumpAndSettle();
      expect(seasonsIn(nav.shuffle!), {'Season 2', 'Season 3', 'Specials'});
      await tester.runAsync(model.settle);
    });

    testWidgets('TV: Shuffle on the page; one season and Seasons in the shuffle under More options', (tester) async {
      await tester.runAsync(scan);
      final nav = _Nav();
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await pumpPage(tester, nav, const TvCollectionPage(name: 'Silo'), tv: true);

      await tester.tap(find.byKey(const ValueKey('tv-page-shuffle')));
      await tester.pump();
      expect(seasonsIn(nav.shuffle!), {'Season 1', 'Season 2', 'Season 3'});

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      // The season tab showing is Season 1 (where the next episode is).
      await tester.tap(find.text('Shuffle Season 1'));
      await tester.pumpAndSettle();
      expect(seasonsIn(nav.shuffle!), {'Season 1'});

      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seasons in the shuffle'));
      await tester.pumpAndSettle();
      // OK on a season takes it out; the panel opens again with it ticked off.
      await tester.tap(find.text('Season 2').last); // in the panel, not the season tab under it
      await tester.pumpAndSettle();
      await tester.runAsync(model.settle);
      expect(find.text('8 videos in the shuffle · OK puts a season in or takes it out'), findsOneWidget);
      await tester.tap(find.text('Shuffle now'));
      await tester.pumpAndSettle();
      expect(seasonsIn(nav.shuffle!), {'Season 1', 'Season 3'});
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
