// Video genres (4 Nov 2026): several genres in one line, Jellyfin's whole list, filtering and
// sorting by genre, .nfo files with one <genre> per genre, and genres looked up online for
// collections with none (services/video_genre_lookup.dart, VideoLibraryModel).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_genre_lookup.dart';
import 'package:hometunes/services/video_nfo.dart';
import 'package:hometunes/state/filters.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_filters.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_types.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

VideoItem _v(String id, String collection, {String? category = 'TV', String? genre, int? episode, int? year}) => VideoItem(
      id: 'jf:s1:$id',
      path: 'jellyfin://s1/$id.mkv',
      title: '$collection $id',
      collection: collection,
      category: category,
      genre: genre,
      year: year,
      season: episode == null ? null : 1,
      episode: episode,
    );

/// Answers from a list instead of going online, and remembers what it was asked.
class _FakeLookup extends VideoGenreLookup {
  final Map<String, GenreFind> answers;
  final asked = <String>[];
  _FakeLookup(this.answers);

  @override
  Future<GenreFind> find(String name, {String? type, int? year}) async {
    asked.add(name);
    return answers[name] ?? const GenreFind([]);
  }
}

void main() {
  test('a genre line splits into genres, each once', () {
    expect(genresIn('Comedy, Drama'), ['Comedy', 'Drama']);
    expect(genresIn('Comedy; drama | Sci-Fi / Horror'), ['Comedy', 'drama', 'Sci-Fi', 'Horror']);
    expect(genresIn('Action & Adventure'), ['Action & Adventure']);
    expect(genresIn('Drama, drama ,  '), ['Drama']);
    expect(genresIn(null), isEmpty);
    expect(genreLine(['Drama', 'Sci-Fi', 'drama']), 'Drama, Sci-Fi');
    expect(genreLine(const []), isNull);
    expect(_v('1', 'Silo', genre: 'Drama, Sci-Fi').genres, ['Drama', 'Sci-Fi']);
  });

  test('a collection\'s genres: the commonest first', () {
    final c = VideoCollection(name: 'Silo', videos: [
      _v('1', 'Silo', genre: 'Sci-Fi'),
      _v('2', 'Silo', genre: 'Drama, Sci-Fi'),
      _v('3', 'Silo', genre: 'Drama, Mystery, Sci-Fi'),
      _v('4', 'Silo'),
    ]);
    expect(c.genres, ['Sci-Fi', 'Drama', 'Mystery']);
    expect(collectionGenre(c), 'Sci-Fi');
    expect(const VideoCollection(name: 'X', videos: [], genre: 'Comedy, Drama').genres, ['Comedy', 'Drama']);
  });

  test('filters, the TV\'s choices and the Genre sorts use every genre', () {
    final silo = _v('s1', 'Silo', genre: 'Drama, Sci-Fi', episode: 1);
    final dune = _v('d1', 'Dune', category: 'Films', genre: 'Sci-Fi');
    final daria = _v('a1', 'Daria', genre: 'Comedy', episode: 1);
    final clip = _v('c1', 'Clips', category: null);
    final videos = [silo, dune, daria, clip];

    final drama = const Filters().withValue('Genre', 'Drama');
    expect(filterVideos(videos, drama), [silo]);
    expect(filterVideos(videos, const Filters().withValue('Genre', 'Sci-Fi')), [silo, dune]);
    final field = videoFilterFields.firstWhere((f) => f.label == 'Genre');
    expect(Filters.none.choices(videos, videoFilterFields, field), {'Comedy': 1, 'Drama': 1, 'Sci-Fi': 2});

    // Listed under each genre they have, A–Z, then the ones with none.
    final groups = sortVideos(videos, VideoSort.genre);
    expect([for (final (h, l) in groups) '$h:${l.map((v) => v.collection).join(',')}'],
        ['Comedy:Daria', 'Drama:Silo', 'Sci-Fi:Dune,Silo', '$noGenreHeading:Clips']);
    expect(videoSortWords(VideoSort.genre), isNotNull);

    final collections = [
      for (final v in videos) VideoCollection(name: v.collection, videos: [v], category: v.category, genre: v.genre),
    ];
    expect([for (final (h, l) in sortCollections(collections, CollectionSort.genre)) '$h:${l.map((c) => c.name).join(',')}'],
        ['Comedy:Daria', 'Drama:Silo', 'Sci-Fi:Dune,Silo', '$noGenreHeading:Clips']);
    final cField = collectionFilterFields.firstWhere((f) => f.label == 'Genre');
    expect(Filters.none.choices(collections, collectionFilterFields, cField), {'Comedy': 1, 'Drama': 1, 'Sci-Fi': 2});

    // The TV.
    final states = {for (final c in collections) c: WatchState.notStarted};
    List<String> names(VideoChoice choice) =>
        [for (final c in chooseCollections(collections, choice, stateOf: (c) => states[c]!)) c.name];
    expect(names(const VideoChoice(genre: 'Drama')), ['Silo']);
    expect(names(const VideoChoice(genre: 'sci-fi')), ['Silo', 'Dune']);
    expect(genresOf(collections: collections), ['Comedy', 'Drama', 'Sci-Fi']);
    expect([for (final c in byGenre<VideoCollection>(collections, (c) => c.genres, (c) => c.name)) c.name],
        ['Daria', 'Silo', 'Dune', 'Clips']);
  });

  test('.nfo files: every <genre> read, one <genre> written per genre', () {
    const xml = '<episodedetails><title>Machines</title><genre>Drama</genre><genre>Sci-Fi, Mystery</genre></episodedetails>';
    expect(parseNfo(xml).genre, 'Drama, Sci-Fi, Mystery');
    final out = updateNfo(xml, 'episodedetails', {'genre': 'Comedy, Drama'});
    expect(RegExp(r'<genre>([^<]*)</genre>').allMatches(out).map((m) => m[1]), ['Comedy', 'Drama']);
    expect(out, contains('<title>Machines</title>'));
    final none = updateNfo(out, 'episodedetails', {'genre': null});
    expect(none, isNot(contains('<genre>')));
  });

  group('looking genres up online', () {
    MockClient answering(Map<String, Object> byHost) => MockClient((r) async {
          final body = byHost[r.url.host];
          if (body == null) return http.Response('not found', 404);
          if (body is int) return http.Response('busy', body);
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
        });

    test('TVmaze for a series: only a show with the same name counts', () async {
      final lookup = VideoGenreLookup(
          client: answering({
        'api.tvmaze.com': [
          {'score': 0.9, 'show': {'name': 'Silo Stories', 'genres': ['Horror'], 'premiered': '2020-01-01'}},
          {'score': 0.8, 'show': {'name': 'Silo', 'genres': ['Drama', 'Science-Fiction'], 'premiered': '2023-05-05'}},
        ],
      }));
      final found = await lookup.find('Silo (2023)', type: 'TV', year: 2023);
      expect((found.genres, found.source), (['Drama', 'Science-Fiction'], 'TVmaze'));
      expect((await lookup.find('Silos', type: 'TV')).found, isFalse);
    });

    test('AniList for anime (any of its titles), iTunes for films', () async {
      final lookup = VideoGenreLookup(
          client: answering({
        'graphql.anilist.co': {
          'data': {
            'Page': {
              'media': [
                {
                  'title': {'romaji': 'Shingeki no Kyojin', 'english': 'Attack on Titan'},
                  'synonyms': ['AoT'],
                  'seasonYear': 2013,
                  'genres': ['Action', 'Drama', 'Fantasy', 'Mystery', 'Horror'],
                }
              ]
            }
          }
        },
        'itunes.apple.com': {
          'results': [
            {'trackName': 'Dune', 'primaryGenreName': 'Sci-Fi & Fantasy', 'releaseDate': '2021-10-22T07:00:00Z'},
            {'trackName': 'Dune', 'primaryGenreName': 'Drama', 'releaseDate': '1984-12-14T08:00:00Z'},
          ]
        },
      }));
      final anime = await lookup.find('Shingeki no Kyojin', type: 'Anime');
      expect((anime.genres, anime.source), (['Action', 'Drama', 'Fantasy', 'Mystery'], 'AniList')); // at most 4
      expect((await lookup.find('Dune', type: 'Films', year: 1984)).genres, ['Drama']);
      expect((await lookup.find('Dune', type: 'Films', year: 2021)).genres, ['Sci-Fi & Fantasy']);
    });

    test('a service that fails makes it "incomplete", not "nothing found"', () async {
      final lookup = VideoGenreLookup(client: answering({'api.tvmaze.com': 503, 'graphql.anilist.co': 500}));
      final found = await lookup.find('Silo', type: 'TV');
      expect((found.found, found.incomplete), (false, true));
      expect(VideoGenreLookup.matches('The Office', 'Office'), isTrue);
      expect(VideoGenreLookup.matches('Brooklyn Nine-Nine', 'Brooklyn Nine Nine'), isTrue);
      expect(VideoGenreLookup.matches('Dune', 'Dune', year: 2021, foundYear: 1984), isFalse);
    });
  });

  group('VideoLibraryModel', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel model;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_video_genres');
      storage = Storage.at(dir);
      Directory(storage.artDir).createSync(recursive: true);
      lib = LibraryModel(storage);
      model = VideoLibraryModel(storage, lib);
    });
    tearDown(() async {
      await model.settle();
      model.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a video with no genre takes its collection\'s; one emptied on purpose stays empty', () async {
      model.setServerVideos('s1', [
        _v('1', 'Silo', genre: 'Drama, Sci-Fi', episode: 1),
        _v('2', 'Silo', episode: 2),
        _v('3', 'Silo', episode: 3),
      ]);
      expect(model.byId('jf:s1:2')!.genres, ['Drama', 'Sci-Fi']);
      await model.setEdit('jf:s1:3', const VideoEdit(cleared: {'genre'}));
      expect(model.byId('jf:s1:3')!.genre, isNull);
      expect(model.rawById('jf:s1:2')!.genre, isNull); // as the server has it
    });

    test('collections with no genre are looked up, found ones kept and saved, misses not asked again', () async {
      final lookup = _FakeLookup({
        'Daria': const GenreFind(['Animation', 'Comedy'], source: 'TVmaze'),
        'Down': const GenreFind([], incomplete: true),
      });
      model.genreLookup = lookup;
      model.setServerVideos('s1', [
        _v('d1', 'Daria', episode: 1),
        _v('d2', 'Daria', episode: 2),
        _v('n1', 'Nowhere', episode: 1),
        _v('w1', 'Down', episode: 1),
        _v('s1', 'Silo', genre: 'Drama', episode: 1),
        _v('h1', 'Birthday party', category: null), // a home video: not looked up
      ]);
      await model.lookUpMissingGenres(gap: Duration.zero);
      expect(lookup.asked..sort(), ['Daria', 'Down', 'Nowhere']);
      expect(model.collectionNamed('Daria')!.genres, ['Animation', 'Comedy']);
      expect(model.byId('jf:s1:d2')!.genre, 'Animation, Comedy');
      expect(model.foundGenreOf(model.collectionNamed('Daria')!)?.source, 'TVmaze');
      expect(model.collectionNamed('Nowhere')!.genres, isEmpty);

      // Again: only the one that couldn't be reached is due (after an hour), so nothing now.
      lookup.asked.clear();
      await model.lookUpMissingGenres(gap: Duration.zero);
      expect(lookup.asked, isEmpty);

      // Switched off: nothing is looked up.
      await lib.setOnlineVideoGenres(false);
      model.forgetFoundGenres();
      await model.lookUpMissingGenres(gap: Duration.zero);
      expect(lookup.asked, isEmpty);
      await lib.setOnlineVideoGenres(true);

      // Found again, and kept in videos.json: a new model has them without asking.
      await model.lookUpMissingGenres(gap: Duration.zero);
      expect(lookup.asked, contains('Daria'));
      await model.settle();
      final again = VideoLibraryModel(storage, lib);
      await again.load();
      again.setServerVideos('s1', [_v('d1', 'Daria', episode: 1)]);
      expect(again.byId('jf:s1:d1')!.genre, 'Animation, Comedy');
      again.dispose();
    });

    test('the user\'s own genre wins over one found online', () async {
      model.genreLookup = _FakeLookup({'Daria': const GenreFind(['Animation'], source: 'TVmaze')});
      model.setServerVideos('s1', [_v('d1', 'Daria', episode: 1)]);
      await model.lookUpMissingGenres(gap: Duration.zero);
      expect(model.byId('jf:s1:d1')!.genre, 'Animation');
      await model.editCollection(model.collectionNamed('Daria')!, genre: 'Comedy, Satire');
      expect(model.byId('jf:s1:d1')!.genres, ['Comedy', 'Satire']);
      expect(model.collectionNamed('Daria')!.genres, ['Comedy', 'Satire']);
    });
  });
}
