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
