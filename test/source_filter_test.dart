// 0.2.2 (step 2 of the Servers & Downloads plan): the Source filter on every tab ("On this
// device", "Streamed", "Downloaded") and the marks on streamed and downloaded things.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/state/book_index.dart' show bookFields;
import 'package:hometunes/state/music_filters.dart';
import 'package:hometunes/state/source_filter.dart';
import 'package:hometunes/state/video_filters.dart';
import 'package:hometunes/ui/widgets/filter_sheet.dart';
import 'package:hometunes/ui/widgets/source_mark.dart';

Track song(String id, {bool server = false}) => Track(
      id: server ? 'server:$id' : 'local:/music/$id.mp3',
      source: server ? TrackSource.server : TrackSource.local,
      title: id,
      artist: 'A',
      album: 'B',
      albumArtist: 'A',
    );

VideoItem video(String id, {bool server = false, String collection = 'Silo'}) => VideoItem(
      id: server ? 'jf:s1:$id' : 'video:/v/$id.mkv',
      path: server ? 'jellyfin://s1/$id.mkv' : '/v/$id.mkv',
      title: id,
      collection: collection,
    );

void main() {
  tearDown(() => MediaSources.downloaded = (_) => false);

  test('each song and video knows where it comes from', () {
    expect(sourceOfTrack(song('a')), MediaSource.local);
    expect(sourceOfTrack(song('b', server: true)), MediaSource.streamed);
    expect(sourceOfVideo(video('c')), MediaSource.local);
    expect(sourceOfVideo(video('d', server: true)), MediaSource.streamed);
    // Once downloads exist (step 3), a downloaded one says so.
    MediaSources.downloaded = (id) => id == 'jf:s1:d' || id == 'server:b';
    expect(sourceOfVideo(video('d', server: true)), MediaSource.downloaded);
    expect(sourceOfTrack(song('b', server: true)), MediaSource.downloaded);
  });

  test('every tab has the Source field first, and it filters', () {
    for (final label in [
      songFields.first.label,
      albumFields.first.label,
      artistFields.first.label,
      bookFields.first.label,
      videoFilterFields.first.label,
      collectionFilterFields.first.label,
    ]) {
      expect(label, 'Source');
    }
    final songs = [song('a'), song('b', server: true), song('c', server: true)];
    final source = songFields.first;
    expect(Filters.none.choices(songs, songFields, source), {'On this device': 1, 'Streamed': 2});
    final streamed = const Filters().withValue('Source', 'Streamed');
    expect([for (final s in songs) if (streamed.matches(s, songFields)) s.title], ['b', 'c']);

    final videos = [video('e'), video('f', server: true)];
    expect(filterVideos(videos, const Filters().withValue('Source', 'On this device')).map((v) => v.title), ['e']);
    expect(filterVideos(videos, streamed).map((v) => v.title), ['f']);
  });

  test('a collection with both kinds matches either, and is marked as partly streamed', () {
    final mixed = VideoCollection(name: 'Silo', videos: [video('a'), video('b', server: true)]);
    final local = VideoCollection(name: 'Home', videos: [video('c', collection: 'Home')]);
    final field = collectionFilterFields.first;
    expect(field.values(mixed).toSet(), {'On this device', 'Streamed'});
    expect(Filters.none.choices([mixed, local], collectionFilterFields, field), {'On this device': 2, 'Streamed': 1});
    expect(markFor(sourcesOfVideos(mixed.videos)), MediaSource.streamed);
    expect(markFor(sourcesOfVideos(local.videos)), isNull);
    MediaSources.downloaded = (_) => true;
    expect(markFor(sourcesOfVideos(mixed.videos)), MediaSource.downloaded);
  });

  Future<void> openSheet(WidgetTester tester, List<Track> songs) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFilterSheet<Track>(
              context,
              items: songs,
              fields: songFields,
              current: Filters.none,
              showLabel: 'Show songs',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet only offers Source when there is more than one', (tester) async {
    await openSheet(tester, [song('a'), song('b')]);
    expect(find.byKey(const ValueKey('filter-Source')), findsNothing);
    expect(find.byKey(const ValueKey('filter-Artist')), findsOneWidget);
    Navigator.of(tester.element(find.text('Show only'))).pop();
    await tester.pumpAndSettle();

    await openSheet(tester, [song('a'), song('b', server: true)]);
    expect(find.byKey(const ValueKey('filter-Source')), findsOneWidget);
  });

  testWidgets('the marks: a cloud for streamed, a cloud with a tick for downloaded, none for your own',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ?SourceBadge.forSources({MediaSource.local}),
          ?SourceBadge.forSources({MediaSource.local, MediaSource.streamed}),
          const SourceInline(MediaSource.downloaded),
          const SourceInline(MediaSource.local),
        ]),
      ),
    ));
    expect(find.byKey(const ValueKey('source-mark-streamed')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-mark-downloaded')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-mark-local')), findsNothing);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.byTooltip('Some of it streams from a server'), findsOneWidget);
  });
}
