// Tests for the "look up song / album details online" feature (services/music_info.dart), which
// asks MusicBrainz for things like year, track numbers and genres. Everything is tested from
// hand-written fake replies, so no internet is needed: building the search addresses, ranking
// the matches, reading artist credits, genres and track lists, and matching the user's song
// titles to an album's track list.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/music_info.dart';

void main() {
  test('song query uses title, artist and album', () {
    final u = MusicInfoSearch.songQuery(title: 'Airbag', artist: 'Radiohead', album: 'OK Computer');
    expect(u.path, '/ws/2/recording/');
    expect(u.queryParameters['query'], 'recording:"Airbag" AND artist:"Radiohead" AND release:"OK Computer"');
    expect(MusicInfoSearch.songQuery(title: 'Airbag').queryParameters['query'], 'recording:"Airbag"');
  });

  test('album query', () {
    final u = MusicInfoSearch.albumQuery(artist: 'Radiohead', album: 'Kid A');
    expect(u.path, '/ws/2/release-group/');
    expect(u.queryParameters['query'], 'releasegroup:"Kid A" AND artist:"Radiohead"');
  });

  // A fake reply with one song on two releases: a live bootleg (listed first) and the official
  // studio album. The official album should be ranked first and marked as preferred.
  test('song matches: official studio albums first, with track + disc numbers', () {
    final matches = MusicInfoSearch.parseSongMatches({
      'recordings': [
        {
          'title': 'Airbag',
          'first-release-date': '1997-05-21',
          'artist-credit': [
            {'name': 'Radiohead'}
          ],
          'releases': [
            {
              'title': 'Live in Berlin',
              'status': 'Bootleg',
              'release-group': {
                'id': 'live',
                'primary-type': 'Album',
                'secondary-types': ['Live']
              },
              'media': [
                {
                  'position': 2,
                  'track': [
                    {'number': '1', 'title': 'Airbag'}
                  ]
                }
              ],
            },
            {
              'title': 'OK Computer',
              'status': 'Official',
              'date': '1997-05-21',
              'artist-credit': [
                {'name': 'Radiohead'}
              ],
              'release-group': {'id': 'okc', 'primary-type': 'Album'},
              'media': [
                {
                  'position': 1,
                  'track': [
                    {'number': '1', 'title': 'Airbag'}
                  ]
                }
              ],
            },
          ],
        },
      ],
    });
    expect(matches.first.album, 'OK Computer');
    expect(matches.first.preferred, isTrue);
    expect(matches.first.year, 1997);
    expect(matches.first.trackNumber, 1);
    expect(matches.first.discNumber, 1);
    expect(matches.last.album, 'Live in Berlin');
    expect(matches.last.discNumber, 2);
    expect(matches.last.year, 1997); // falls back to the recording's first release
  });

  // MusicBrainz splits credits into parts joined by phrases like " feat. "; they're glued back.
  test('artist credits keep "feat." join phrases', () {
    final m = MusicInfoSearch.parseAlbumMatches({
      'release-groups': [
        {
          'id': 'x',
          'title': 'Song',
          'first-release-date': '2020',
          'artist-credit': [
            {'name': 'A', 'joinphrase': ' feat. '},
            {'name': 'B'}
          ],
        }
      ]
    });
    expect(m.single.artist, 'A feat. B');
    expect(m.single.year, 2020);
  });

  // MusicBrainz genres come with vote counts; the most voted come first.
  test('genres: most votes first, capitalised', () {
    final g = MusicInfoSearch.parseGenres({
      'genres': [
        {'name': 'rock', 'count': 13},
        {'name': 'alternative rock', 'count': 25},
        {'name': 'britpop', 'count': 1},
      ]
    });
    expect(g, ['Alternative Rock', 'Rock', 'Britpop']);
  });

  // When an album has several releases, pick the official one whose track count matches the
  // number of songs the user has (3 here), not simply the first or biggest one.
  test('track list: prefers the official release with the same number of tracks', () {
    Map<String, dynamic> release(String status, int n) => {
          'status': status,
          'media': [
            {
              'position': 1,
              'tracks': [
                for (var i = 1; i <= n; i++) {'number': '$i', 'title': 'Song $i'}
              ]
            }
          ],
        };
    final list = MusicInfoSearch.parseTracklist({
      'releases': [release('Official', 12), release('Bootleg', 3), release('Official', 3)],
    }, preferTrackCount: 3);
    expect(list.length, 3);
    expect(list.last.number, 3);
    expect(list.last.disc, 1);
  });

  // Each of the user's titles is matched to an album track (or null if none fits): case,
  // "&" vs "and" and extras in brackets are ignored.
  test('titles match despite case, punctuation and "(Remastered)"', () {
    final tracks = const [
      TrackInfo(1, 1, 'Airbag'),
      TrackInfo(1, 2, 'Paranoid Android'),
      TrackInfo(2, 1, 'Rock & Roll'),
    ];
    final m = MusicInfoSearch.matchTracks(
      ['paranoid android (Remastered 2017)', 'AIRBAG', 'Rock and Roll', 'Not on album'],
      tracks,
    );
    expect(m[0]!.number, 2);
    expect(m[1]!.number, 1);
    expect(m[2]!.disc, 2);
    expect(m[3], isNull);
  });
}
