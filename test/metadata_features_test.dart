// Tests for editing song details in the files themselves and for the online cover search:
// which fields each file type can store (TagSupport in services/tag_writer.dart), writing tags
// into a real (tiny, generated) WAV file with a backup copy, and building / reading MusicBrainz
// cover search requests (services/cover_search.dart) without going online.
// silentWav() is also used by scan_test.dart to make test files.
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/cover_search.dart';
import 'package:hometunes/services/tag_writer.dart';
import 'package:path/path.dart' as p;

/// A tiny valid WAV file: 0.1 s of silence, 8 kHz mono 16-bit.
Uint8List silentWav() {
  const sampleRate = 8000, samples = 800;
  final data = ByteData(44 + samples * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  // Standard 44-byte WAV header, then the (all-zero) samples.
  str(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  // leftover(edit) = the parts of an edit the file type can't hold. Those stay as HomeTunes-only
  // edits instead of being written into the file.
  group('Which fields each format can store', () {
    test('MP3 and FLAC take everything', () {
      const edit = TrackEdit(title: 'T', albumArtist: 'AA', art: '/c.jpg');
      expect(TagSupport.forPath('a.mp3').leftover(edit).isEmpty, isTrue);
      expect(TagSupport.forPath('a.FLAC').leftover(edit).isEmpty, isTrue);
    });

    test('M4A keeps album artist as a HomeTunes edit', () {
      final left = TagSupport.forPath('a.m4a').leftover(const TrackEdit(title: 'T', albumArtist: 'AA'));
      expect(left.title, isNull);
      expect(left.albumArtist, 'AA');
    });

    // "Keeps" = kept as a HomeTunes edit. OGG files can't be written at all (`anything` is false).
    test('WAV keeps cover and disc number; OGG keeps everything', () {
      final wav = TagSupport.forPath('a.wav').leftover(const TrackEdit(title: 'T', discNumber: 2, art: '/c.jpg'));
      expect(wav.title, isNull);
      expect(wav.discNumber, 2);
      expect(wav.art, '/c.jpg');
      expect(TagSupport.forPath('a.ogg').anything, isFalse);
    });

    // The first few bytes of an image ("magic numbers") tell JPEG from PNG, whatever its name.
    test('image type is detected from the bytes', () {
      expect(imageMimeType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(imageMimeType([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0]), 'image/png');
      expect(imageMimeType([1, 2, 3, 4]), isNull);
    });
  });

  group('Writing tags into a real file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_tags'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('WAV: new title/artist/album are written and a backup is kept', () async {
      final file = File(p.join(dir.path, 'song.wav'))..writeAsBytesSync(silentWav());
      final backups = p.join(dir.path, 'backups');

      final result = await writeTagsToFile(
        file.path,
        const TrackEdit(title: 'New Title', artist: 'New Artist', album: 'New Album', discNumber: 3),
        backupDir: backups,
      );

      expect(result.ok, isTrue, reason: result.error);
      expect(result.leftover.discNumber, 3); // WAV can't store disc numbers
      final m = readMetadata(file);
      expect(m.title, 'New Title');
      expect(m.artist, 'New Artist');
      expect(m.album, 'New Album');
      expect(File(p.join(backups, 'song.wav')).existsSync(), isTrue);
    });

    // Also shows the file's bytes are left exactly as they were.
    test('unsupported types are refused without touching the file', () async {
      final file = File(p.join(dir.path, 'song.ogg'))..writeAsBytesSync([1, 2, 3]);
      final result = await writeTagsToFile(file.path, const TrackEdit(title: 'X'));
      expect(result.ok, isFalse);
      expect(file.readAsBytesSync(), [1, 2, 3]);
    });
  });

  // Covers are looked up on MusicBrainz and the pictures come from the Cover Art Archive.
  group('Online cover search', () {
    test('album search includes album and artist', () {
      final u = CoverSearch.buildQuery(artist: 'Radiohead', album: 'OK Computer');
      expect(u.host, 'musicbrainz.org');
      expect(u.path, '/ws/2/release-group/');
      expect(u.queryParameters['query'], 'releasegroup:"OK Computer" AND artist:"Radiohead"');
      expect(u.queryParameters['fmt'], 'json');
    });

    test('song title + artist searches recordings; quotes are stripped', () {
      final u = CoverSearch.buildQuery(artist: 'A "B"', title: 'Song');
      expect(u.path, '/ws/2/recording/');
      expect(u.queryParameters['query'], 'recording:"Song" AND artist:"A  B"');
    });

    // A fake MusicBrainz reply: an album found directly plus the same album again via a song
    // search (which also turns up a second edition). The duplicate "rg1" must appear only once.
    test('parses release groups and recordings, without duplicates', () {
      final results = CoverSearch.parseResults({
        'release-groups': [
          {
            'id': 'rg1',
            'title': 'OK Computer',
            'first-release-date': '1997-05-21',
            'artist-credit': [
              {'name': 'Radiohead'}
            ],
          },
        ],
        'recordings': [
          {
            'artist-credit': [
              {'name': 'Radiohead'}
            ],
            'releases': [
              {
                'date': '1997',
                'release-group': {'id': 'rg1', 'title': 'OK Computer'}
              },
              {
                'date': '2009-03-24',
                'release-group': {'id': 'rg2', 'title': 'OK Computer (Collector\'s Edition)'}
              },
            ],
          },
        ],
      });
      expect(results.map((r) => r.id), ['rg1', 'rg2']);
      expect(results.first.year, '1997');
      expect(results.first.artist, 'Radiohead');
      expect(results.last.artist, 'Radiohead');
      expect(CoverSearch.thumbnailUrl('rg1').toString(),
          'https://coverartarchive.org/release-group/rg1/front-250');
    });
  });
}
