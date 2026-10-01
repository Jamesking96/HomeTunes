// "Search online" for video pictures (services/video_art_search.dart), against fake TVmaze,
// AniList and Wikipedia answers shaped like the real ones (checked with tool/probe_video_art.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/video_art_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response json(Object body, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  final asked = <String>[];
  MockClient fake({bool anilistDown = false}) => MockClient((r) async {
        asked.add('${r.url.host}${r.url.path}');
        expect(r.headers['User-Agent'], startsWith('HomeTunes/'));
        final u = r.url;
        if (u.host == 'api.tvmaze.com') {
          if (u.path == '/search/shows') {
            return json([
              {'score': 0.9, 'show': {'id': 38052, 'name': 'Silo', 'premiered': '2023-05-05'}},
              {'score': 0.2, 'show': {'id': 1, 'name': 'Silo Stories'}},
            ]);
          }
          if (u.path == '/shows/38052/episodebynumber') {
            expect(u.queryParameters, {'season': '1', 'number': '2'});
            return json({'name': "Holston's Pick", 'image': {'medium': 'https://tv/ep-m.jpg', 'original': 'https://tv/ep.jpg'}});
          }
          if (u.path == '/shows/38052/images') {
            return json([
              {'type': 'background', 'main': false, 'resolutions': {'original': {'url': 'https://tv/bg.jpg', 'width': 3840, 'height': 2160}}},
              {'type': 'poster', 'main': true, 'resolutions': {
                'original': {'url': 'https://tv/p.jpg', 'width': 2000, 'height': 3000},
                'medium': {'url': 'https://tv/p-m.jpg', 'width': 210, 'height': 295}}},
              {'type': 'typography', 'resolutions': {'original': {'url': 'https://tv/t.png'}}},
            ]);
          }
        }
        if (u.host == 'graphql.anilist.co') {
          if (anilistDown) return http.Response('busy', 500);
          final body = jsonDecode(r.body) as Map;
          expect((body['variables'] as Map)['search'], 'Silo');
          return json({'data': {'Page': {'media': [
            {'title': {'romaji': 'Silo', 'english': null}, 'seasonYear': 2020, 'format': 'OVA',
              'coverImage': {'large': 'https://ani/c-l.jpg', 'extraLarge': 'https://ani/c.jpg'}, 'bannerImage': null},
          ]}}});
        }
        if (u.host == 'en.wikipedia.org') {
          final q = u.queryParameters;
          if (q['action'] == 'query' && q['generator'] == 'search') {
            expect(q['gsrsearch'], 'Silo TV series');
            return json({'query': {'pages': [
              {'title': 'Silo', 'index': 2, 'description': 'Structure for storing crops',
                'original': {'source': 'https://up/bins.jpg', 'width': 800, 'height': 600}},
              {'title': 'Silo (TV series)', 'index': 1, 'description': '2023 TV series'},
            ]}});
          }
          if (q['action'] == 'parse') {
            return json({'parse': {'wikitext': q['page'] == 'Silo (TV series)'
                ? '{{Infobox television\n| image = Silo title card.png <!-- the card -->\n| genre = SF\n}}'
                : '{{Short description}}'}});
          }
          if (q['action'] == 'query' && q['prop'] == 'imageinfo') {
            expect(q['titles'], 'File:Silo title card.png');
            return json({'query': {'pages': [
              {'title': 'File:Silo title card.png', 'imageinfo': [
                {'url': 'https://up/card.png', 'thumburl': 'https://up/card-400.png', 'width': 1920, 'height': 1080, 'mime': 'image/png'}]},
            ]}});
          }
        }
        return http.Response('not found', 404);
      });

  test('every service is asked; results come back in order, with an episode still', () async {
    final s = VideoArtSearch(client: fake());
    final r = await s.search('Silo', season: 1, episode: 2, wikipediaHint: 'TV series');
    expect(r.failed, isEmpty);
    expect([for (final c in r.found) '${c.source}:${c.kind}:${c.fullUrl}'], [
      'TVmaze:Episode:https://tv/ep.jpg',
      'TVmaze:Poster:https://tv/p.jpg',
      'TVmaze:Background:https://tv/bg.jpg',
      'AniList:Cover:https://ani/c.jpg',
      'Wikipedia:Picture:https://up/card.png', // the infobox picture, best article first
      'Wikipedia:Picture:https://up/bins.jpg',
    ]);
    expect(r.found.first.title, contains('S1 E2'));
    expect(r.found[1].previewUrl, 'https://tv/p-m.jpg');
    expect(r.found[1].tall, isTrue);
    expect(r.found[2].tall, isFalse);
    expect(r.found[1].title, 'Silo (2023)');
    // The weak second TVmaze match isn't used.
    expect(asked.where((a) => a.contains('/shows/1/')), isEmpty);
  });

  test('one service failing leaves the others', () async {
    final r = await VideoArtSearch(client: fake(anilistDown: true)).search('Silo', order: const ['AniList', 'TVmaze']);
    expect(r.failed, ['AniList']);
    expect(r.found.map((c) => c.source).toSet(), {'TVmaze'});
    expect((await VideoArtSearch(client: fake()).search('  ')).found, isEmpty);
  });

  test('infobox pictures and picture bytes', () {
    expect(VideoArtSearch.infoboxImage('| image = [[File:Poster One.jpg|250px]]'), 'Poster One.jpg');
    expect(VideoArtSearch.infoboxImage('|image=File:Two.JPEG'), 'Two.JPEG');
    expect(VideoArtSearch.infoboxImage('| image = \n| caption = x'), isNull);
    expect(VideoArtSearch.infoboxImage('| image = Logo.svg'), isNull);
    expect(VideoArtSearch.looksLikePicture([0xFF, 0xD8, 0xFF, 0xE0]), isTrue);
    expect(VideoArtSearch.looksLikePicture(utf8.encode('<html>')), isFalse);
  });

  test('download falls back to the small picture, and refuses a web page', () async {
    final s = VideoArtSearch(client: MockClient((r) async => r.url.path == '/big.jpg'
        ? http.Response('gone', 404)
        : r.url.path == '/small.jpg'
            ? http.Response.bytes([0xFF, 0xD8, 0xFF, 0xE0, 1, 2], 200)
            : http.Response('<html>', 200)));
    const c = VideoArtCandidate(
        source: 'TVmaze', title: 't', kind: 'Poster', previewUrl: 'https://x/small.jpg', fullUrl: 'https://x/big.jpg');
    expect(await s.download(c), [0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);
    const bad = VideoArtCandidate(
        source: 'TVmaze', title: 't', kind: 'Poster', previewUrl: 'https://x/page', fullUrl: 'https://x/page');
    await expectLater(s.download(bad), throwsFormatException);
  });
}
