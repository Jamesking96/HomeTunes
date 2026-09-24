import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/state/play_queue.dart';

const song = Track(
  id: 'local:/music/a.mp3',
  source: TrackSource.local,
  title: 'Original Title',
  artist: 'Old Artist',
  album: 'Old Album',
  albumArtist: 'Old Artist',
  trackNumber: 3,
  year: 1999,
  art: '/art/file-cover.img',
);

void main() {
  test('applying an edit changes only the edited fields', () {
    final t = const TrackEdit(artist: 'New Artist', art: '/art/custom.jpg').applyTo(song);
    expect(t.artist, 'New Artist');
    expect(t.art, '/art/custom.jpg');
    expect(t.title, 'Original Title');
    expect(t.album, 'Old Album');
    expect(t.id, song.id);
    expect(t.path, song.path);
  });

  test('later edits merge over earlier ones', () {
    final first = const TrackEdit(artist: 'A', album: 'X');
    final merged = first.mergedWith(const TrackEdit(album: 'Y', year: 2020));
    expect(merged.artist, 'A');
    expect(merged.album, 'Y');
    expect(merged.year, 2020);
  });

  test('editing a field back to the file value removes the edit', () {
    final e = const TrackEdit(artist: 'Old Artist', album: 'Other').normalizedAgainst(song);
    expect(e.artist, isNull);
    expect(e.album, 'Other');
    expect(const TrackEdit(title: 'Original Title').normalizedAgainst(song).isEmpty, isTrue);
  });

  test('json round trip keeps only set fields', () {
    const e = TrackEdit(title: 'T', trackNumber: 7, art: '/c.png');
    final j = e.toJson();
    expect(j.keys, containsAll(['title', 'trackNumber', 'art']));
    expect(j.containsKey('artist'), isFalse);
    final back = TrackEdit.fromJson(j);
    expect(back.title, 'T');
    expect(back.trackNumber, 7);
    expect(back.art, '/c.png');
  });

  test('edited album name regroups the song', () {
    final t = const TrackEdit(album: 'New Album').applyTo(song);
    expect(t.albumKey, isNot(song.albumKey));
  });

  test('queue picks up edited copies without moving position', () {
    Track t(String id) => Track(id: id, source: TrackSource.local, title: id, artist: 'a', album: 'b', albumArtist: 'a');
    final q = PlayQueue()..setTracks([t('1'), t('2'), t('3')], start: 1);
    final edited = const TrackEdit(title: 'Two!').applyTo(t('2'));
    final changed = q.refresh((id) => id == '2' ? edited : null);
    expect(changed, isTrue);
    expect(q.current!.title, 'Two!');
    expect(q.position, 1);
    expect(q.refresh((_) => null), isFalse);
  });
}
