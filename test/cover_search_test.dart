// Find cover online (9 Oct 2026 fix): an album whose title MusicBrainz punctuates differently
// ("THE E.N.D." is "The E•N•D" there) is found by searching again without punctuation, and a busy
// MusicBrainz is asked again. Fake MusicBrainz and Cover Art Archive answers; no internet.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/cover_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  /// A fake internet: [albums] maps a MusicBrainz query (as sent) to the release-group ids it finds;
  /// every id has a cover. [busy] answers 503 that many times first. Records every query.
  ({http.Client client, List<String> queries}) fake(Map<String, List<String>> albums, {int busy = 0}) {
    final queries = <String>[];
    var busyLeft = busy;
    final client = MockClient((req) async {
      if (req.url.host == 'coverartarchive.org') return http.Response.bytes([1, 2, 3], 200);
      final q = req.url.queryParameters['query']!;
      queries.add(q);
      if (busyLeft > 0) {
        busyLeft--;
        return http.Response('busy', 503);
      }
      final ids = albums[q] ?? const [];
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'release-groups': [
            for (final id in ids)
              {'id': id, 'title': 'The E•N•D', 'artist-credit': [{'name': 'The Black Eyed Peas'}], 'first-release-date': '2009-06-03'},
          ],
        })),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    return (client: client, queries: queries);
  }

  CoverSearch searchWith(http.Client c) => CoverSearch(client: c, pause: Duration.zero, busyWait: Duration.zero);

  test('loosen drops punctuation and symbols, keeping letters and digits in any alphabet', () {
    expect(CoverSearch.loosen('THE E.N.D.'), 'THE E N D');
    expect(CoverSearch.loosen('The E•N•D'), 'The E N D');
    expect(CoverSearch.loosen('AC/DC'), 'AC DC');
    expect(CoverSearch.loosen("Guns N' Roses"), 'Guns N Roses');
    expect(CoverSearch.loosen('Sigur Rós – Ágætis byrjun!'), 'Sigur Rós Ágætis byrjun');
    expect(CoverSearch.loosen('東京事変'), '東京事変');
    expect(CoverSearch.loosen('OK Computer'), 'OK Computer');
  });

  test('an album MusicBrainz punctuates differently is found without the punctuation', () async {
    final net = fake({'releasegroup:"THE E N D" AND artist:"Black Eyed Peas"': ['end']});
    final found = await searchWith(net.client).search(artist: 'Black Eyed Peas', album: 'THE E.N.D.');
    expect(net.queries, [
      'releasegroup:"THE E.N.D." AND artist:"Black Eyed Peas"',
      'releasegroup:"THE E N D" AND artist:"Black Eyed Peas"',
    ]);
    expect(found.single.releaseGroupId, 'end');
    expect(found.single.title, 'The E•N•D');
  });

  test('a match on the exact names is used as it is, with one search', () async {
    final net = fake({'releasegroup:"THE E.N.D." AND artist:"Black Eyed Peas"': ['end']});
    final found = await searchWith(net.client).search(artist: 'Black Eyed Peas', album: 'THE E.N.D.');
    expect(net.queries, hasLength(1));
    expect(found, hasLength(1));
  });

  test('names without punctuation are not searched twice', () async {
    final net = fake({});
    final found = await searchWith(net.client).search(artist: 'Radiohead', album: 'OK Computer');
    expect(found, isEmpty);
    expect(net.queries, hasLength(1));
  });

  test('when no picture arrives from the cover website it says so; albums with no cover are just left out', () async {
    MockClient site(int coverStatus) => MockClient((req) async {
          if (req.url.host == 'coverartarchive.org') return http.Response('', coverStatus);
          return http.Response('{"release-groups":[{"id":"a","title":"Elephunk","artist-credit":[]}]}', 200);
        });
    // The site failed (or was too slow): not "no covers".
    await expectLater(searchWith(site(502)).search(artist: 'Black Eyed Peas', album: 'Elephunk'),
        throwsA(isA<CoverSiteUnavailable>()));
    // It answered "no cover for this album": an empty list, as before.
    expect(await searchWith(site(404)).search(artist: 'Black Eyed Peas', album: 'Elephunk'), isEmpty);
  });

  test('a busy MusicBrainz is asked again, twice at most', () async {
    final ok = fake({'releasegroup:"Elephunk" AND artist:"Black Eyed Peas"': ['e']}, busy: 2);
    expect(await searchWith(ok.client).search(artist: 'Black Eyed Peas', album: 'Elephunk'), hasLength(1));
    expect(ok.queries, hasLength(3));

    final tooBusy = fake({'releasegroup:"Elephunk" AND artist:"Black Eyed Peas"': ['e']}, busy: 3);
    await expectLater(searchWith(tooBusy.client).search(artist: 'Black Eyed Peas', album: 'Elephunk'),
        throwsA(isA<Exception>().having((e) => '$e', 'message', contains('503'))));
  });
}
