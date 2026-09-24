import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/subsonic_client.dart';
import 'package:hometunes/state/library_index.dart';

Track t(String title, String artist, String album, {int? no, int? disc, int? year}) => Track(
      id: 'local:$artist/$album/$title',
      source: TrackSource.local,
      title: title,
      artist: artist,
      album: album,
      albumArtist: artist,
      trackNumber: no,
      discNumber: disc,
      year: year,
      duration: const Duration(minutes: 3),
    );

void main() {
  final tracks = [
    t('So What', 'Miles Davis', 'Kind of Blue', no: 1, year: 1959),
    t('Blue in Green', 'Miles Davis', 'Kind of Blue', no: 3, year: 1959),
    t('Freddie Freeloader', 'Miles Davis', 'Kind of Blue', no: 2, year: 1959),
    t('Disc two opener', 'Miles Davis', 'Kind of Blue', no: 1, disc: 2, year: 1959),
    t('Paranoid Android', 'Radiohead', 'OK Computer', no: 2, year: 1997),
    t('Airbag', 'Radiohead', 'OK Computer', no: 1, year: 1997),
    t('Idioteque', 'Radiohead', 'Kid A', no: 8, year: 2000),
    t('Here Comes the Sun', 'The Beatles', 'Abbey Road', no: 7, year: 1969),
  ];

  test('groups albums and sorts tracks by disc then number', () {
    final albums = groupAlbums(tracks);
    expect(albums.length, 4);
    final kob = albums.firstWhere((a) => a.title == 'Kind of Blue');
    expect(kob.tracks.map((x) => x.title).toList(),
        ['So What', 'Freddie Freeloader', 'Blue in Green', 'Disc two opener']);
    expect(kob.totalDuration, const Duration(minutes: 12));
  });

  test('artist sort ignores "The"', () {
    final artists = groupArtists(groupAlbums(tracks));
    expect(artists.map((a) => a.name).toList(), ['The Beatles', 'Miles Davis', 'Radiohead']);
    final rh = artists.last;
    expect(rh.albums.first.title, 'Kid A'); // newest first
  });

  test('search needs every word and ranks prefix matches first', () {
    final albums = groupAlbums(tracks);
    final artists = groupArtists(albums);
    final r = search('radiohead air', tracks, albums, artists);
    expect(r.tracks.map((x) => x.title).toList(), ['Airbag']);
    final r2 = search('blue', tracks, albums, artists);
    expect(r2.tracks.first.title, 'Blue in Green');
    expect(r2.albums.single.title, 'Kind of Blue');
    expect(search('   ', tracks, albums, artists).isEmpty, isTrue);
  });

  test('track json round trip', () {
    final a = tracks.first;
    final b = Track.fromJson(a.toJson());
    expect(b.id, a.id);
    expect(b.title, a.title);
    expect(b.trackNumber, a.trackNumber);
    expect(b.duration, a.duration);
    expect(b.source, TrackSource.local);
  });

  test('file name fallback parses track numbers', () {
    expect(fallbackFromFileName('03 - Song Name').title, 'Song Name');
    expect(fallbackFromFileName('03 - Song Name').trackNumber, 3);
    expect(fallbackFromFileName('12. Other').trackNumber, 12);
    expect(fallbackFromFileName('Just a title').trackNumber, isNull);
    expect(fallbackFromFileName('Just a title').title, 'Just a title');
  });

  group('Subsonic', () {
    const cfg = ServerConfig(url: 'music.local:4533/', username: 'me', password: 'sesame');
    final c = SubsonicClient(cfg);

    test('base url gets a scheme and loses trailing slashes', () {
      expect(c.baseUrl, 'http://music.local:4533');
    });

    test('token is md5(password + salt)', () {
      // md5("sesamec19b2d") from the Subsonic API docs example.
      final p = c.authParams(salt: 'c19b2d');
      expect(p['t'], '26719a1196d2a940705a59634eb18eab');
      expect(p['u'], 'me');
      expect(p['f'], 'json');
    });

    test('stream url is stable for the same song', () {
      expect(c.streamUrl('42'), c.streamUrl('42'));
      expect(Uri.parse(c.streamUrl('42')).path, '/rest/stream');
      expect(Uri.parse(c.streamUrl('42')).queryParameters['id'], '42');
    });

    test('song json maps to a server track', () {
      final tr = SubsonicClient.songToTrack({
        'id': 'abc',
        'title': 'Song',
        'artist': 'Band',
        'album': 'Record',
        'track': 4,
        'year': 2001,
        'duration': 200,
        'coverArt': 'al-9',
      }, albumArtistFallback: 'Band');
      expect(tr.id, 'server:abc');
      expect(tr.isLocal, isFalse);
      expect(tr.duration, const Duration(seconds: 200));
      expect(tr.art, 'al-9');
      expect(tr.trackNumber, 4);
    });
  });
}
