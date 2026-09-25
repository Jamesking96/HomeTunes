import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/book_sidecar.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:path/path.dart' as p;

/// Shaped like Libation's .metadata.json (Audible's product details), cut down.
Map<String, dynamic> audibleJson({String sequence = '0.1'}) => {
      'asin': 'B000000001',
      'title': 'The Last Kettle',
      'subtitle': 'The Tea Saga, Book 1',
      'authors': [
        {'asin': 'A1', 'name': 'Jane Brewer'},
        {'asin': 'A2', 'name': 'Sam Leaf - translator'},
      ],
      'narrators': [
        {'name': 'Peter Pour'},
        {'name': 'Ann Steep'},
      ],
      'series': [
        {'asin': 'S1', 'sequence': sequence, 'title': 'The Tea Saga'},
      ],
      'category_ladders': [
        {
          'ladder': [
            {'id': '1', 'name': 'Science Fiction & Fantasy'},
            {'id': '2', 'name': 'Fantasy'},
          ],
          'root': 'Genres',
        },
      ],
      'release_date': '2014-02-27',
      'publisher_summary': '<p><b>A kettle</b> &amp; a quest.</p><p>Second&nbsp;part.<br />New line.</p>',
      'product_images': {'500': 'https://example.com/x.jpg'},
      'ChapterInfo': {
        'brandIntroDurationMs': '2000',
        'brandOutroDurationMs': '3000',
        'runtime_length_ms': '65000',
        'chapters': [
          {'length_ms': '10000', 'start_offset_ms': '2000', 'title': 'Opening Credits'},
          {
            'length_ms': '2500',
            'start_offset_ms': '12000',
            'title': 'The Kettle',
            'chapters': [
              {'length_ms': '20000', 'start_offset_ms': '14500', 'title': 'Part I'},
              {'length_ms': '20000', 'start_offset_ms': '34500', 'title': 'Part II'},
            ],
          },
          {'length_ms': '10000', 'start_offset_ms': '54500', 'title': 'End Credits'},
        ],
      },
    };

void main() {
  group('Book metadata files', () {
    test('Libation / Audible: details, roles left out of the author, genres, HTML description', () {
      final info = BookInfo.parse(jsonEncode(audibleJson()))!;
      expect(info.title, 'The Last Kettle');
      expect(info.author, 'Jane Brewer');
      expect(info.narrator, 'Peter Pour, Ann Steep');
      expect(info.series, 'The Tea Saga');
      expect(info.seriesIndex, 0.1);
      expect(info.year, 2014);
      expect(info.genres, ['Fantasy']);
      expect(info.description, 'A kettle & a quest.\n\nSecond part.\nNew line.');
    });

    test('chapters: parts are named after their heading; short headings dropped', () {
      final info = BookInfo.parse(jsonEncode(audibleJson()))!;
      expect(info.chapters.map((c) => c.title),
          ['Opening Credits', 'The Kettle: Part I', 'The Kettle: Part II', 'End Credits']);
    });

    test('chapters line up with files that had Audible\'s intro cut, or not', () {
      final info = BookInfo.parse(jsonEncode(audibleJson()))!;
      // 65 s with the 2 s intro and 3 s outro removed = 60 s.
      final cut = info.chaptersFor(const Duration(seconds: 60));
      expect(cut.first.start, Duration.zero);
      expect(cut[1].start, const Duration(milliseconds: 12500));
      final whole = info.chaptersFor(const Duration(seconds: 65));
      expect(whole.first.start, const Duration(seconds: 2));
      // A very different length: another edition, so no chapters.
      expect(info.chaptersFor(const Duration(minutes: 30)), isEmpty);
    });

    test('series numbers like "1-5" and "" ', () {
      expect(BookInfo.parse(jsonEncode(audibleJson(sequence: '1-5')))!.seriesIndex, 1);
      expect(BookInfo.parse(jsonEncode(audibleJson(sequence: '')))!.seriesIndex, isNull);
    });

    test('Audiobookshelf metadata.json', () {
      final info = BookInfo.parse(jsonEncode({
        'title': 'Brew',
        'authors': ['Jane Brewer'],
        'narrators': ['Peter Pour'],
        'series': ['The Tea Saga #2'],
        'genres': ['Fantasy'],
        'publishedYear': '2019',
        'description': 'Plain words.',
        'chapters': [
          {'id': 0, 'start': 0, 'end': 10.5, 'title': 'One'},
          {'id': 1, 'start': 10.5, 'end': 20, 'title': 'Two'},
        ],
      }))!;
      expect(info.author, 'Jane Brewer');
      expect(info.series, 'The Tea Saga');
      expect(info.seriesIndex, 2);
      expect(info.year, 2019);
      expect(info.description, 'Plain words.');
      expect(info.chapters[1].start, const Duration(milliseconds: 10500));
    });

    test('other JSON files are ignored', () {
      expect(BookInfo.parse('[1,2]'), isNull);
      expect(BookInfo.parse('{"volume": 3}'), isNull);
      expect(BookInfo.parse('not json'), isNull);
    });
  });

  group('Finding the files beside a book', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_sidecar'));
    tearDown(() => dir.deleteSync(recursive: true));

    File touch(String rel, [String text = 'x']) =>
        File(p.join(dir.path, rel))..createSync(recursive: true)..writeAsStringSync(text);

    test('Libation layout: files named after the book', () {
      final book = touch('Kettle [B01]/The Last Kettle [B01].m4b');
      touch('Kettle [B01]/The Last Kettle [B01].jpg');
      touch('Kettle [B01]/The Last Kettle [B01].metadata.json', '{}');
      touch('Kettle [B01]/The Last Kettle [B01].pdf');
      final s = findSidecars(book.path, FolderCache());
      expect(p.basename(s.metadataFile!), 'The Last Kettle [B01].metadata.json');
      expect(s.metadataIsOwn, isTrue);
      expect(p.basename(s.image!), 'The Last Kettle [B01].jpg');
      expect(s.imageIsOwn, isTrue);
      expect(s.companions.map(p.basename), ['The Last Kettle [B01].pdf']);
      expect(s.stamp, isNot(0));
    });

    test('a picture named after the folder, or the only one, is the cover; two unnamed ones are not', () {
      final a = touch('Mentats/Mentats Part 1.mp3');
      touch('Mentats/Mentats Part 2.mp3');
      touch('Mentats/Mentats.jpg');
      touch('Mentats/scan.jpg');
      expect(p.basename(findSidecars(a.path, FolderCache()).image!), 'Mentats.jpg');

      final b = touch('Other/track.mp3');
      touch('Other/whatever.png');
      expect(p.basename(findSidecars(b.path, FolderCache()).image!), 'whatever.png');

      final c = touch('Pair/track.mp3');
      touch('Pair/one.jpg');
      touch('Pair/two.jpg');
      expect(findSidecars(c.path, FolderCache()).image, isNull);
    });

    test('a collection\'s Info.txt describes the books in its folders', () {
      final a = touch('Tea Books/Book 01 - Brew/01.mp3');
      touch('Tea Books/Info.txt', 'All about the tea books.');
      final s = findSidecars(a.path, FolderCache());
      expect(p.basename(s.descriptionFile!), 'Info.txt');
      expect(s.image, isNull);
    });

    test('with several books in one folder, a PDF only goes with its own book', () {
      final a = touch('Shelf/Alpha.m4b');
      touch('Shelf/Beta.m4b');
      touch('Shelf/Beta.pdf');
      expect(findSidecars(a.path, FolderCache()).companions, isEmpty);
    });

    test('scanning reads the details and chapters, and picks up files added later', () async {
      final folder = Directory(p.join(dir.path, 'Kettle'))..createSync();
      File(p.join('test', 'fixtures', 'tagged.m4a')).copySync(p.join(folder.path, 'The Last Kettle.m4b'));
      final artDir = Directory(p.join(dir.path, 'art'))..createSync();
      final scanner = LocalScanner(artDir.path);

      var tracks = await scanner.scan([folder.path]);
      expect(tracks.single.hasBookInfo, isFalse);
      expect(tracks.single.artist, 'Test Artist');

      // The fixture is about a second long: make the metadata describe that.
      final meta = audibleJson();
      (meta['ChapterInfo'] as Map)['runtime_length_ms'] = '${tracks.single.duration.inMilliseconds}';
      (meta['ChapterInfo'] as Map)['brandIntroDurationMs'] = '0';
      (meta['ChapterInfo'] as Map)['brandOutroDurationMs'] = '0';
      (meta['ChapterInfo'] as Map)['chapters'] = [
        {'length_ms': '500', 'start_offset_ms': '0', 'title': 'Start'},
        {'length_ms': '500', 'start_offset_ms': '500', 'title': 'Middle'},
      ];
      File(p.join(folder.path, 'The Last Kettle.metadata.json')).writeAsStringSync(jsonEncode(meta));
      File(p.join(folder.path, 'The Last Kettle.jpg')).writeAsBytesSync([0xFF, 0xD8, 0xFF]);

      final previous = {for (final t in tracks) t.id: t};
      tracks = await scanner.scan([folder.path], previous: previous);
      final t = tracks.single;
      expect(t.hasBookInfo, isTrue);
      expect(t.title, 'The Last Kettle');
      expect(t.album, 'The Last Kettle');
      expect(t.artist, 'Jane Brewer');
      expect(t.narrator, 'Peter Pour, Ann Steep');
      expect(t.series, 'The Tea Saga');
      expect(t.seriesIndex, 0.1);
      expect(t.chapters.map((c) => c.title), ['Start', 'Middle']);
      expect(p.basename(t.art!), 'The Last Kettle.jpg');
      expect(t.description, startsWith('A kettle & a quest.'));

      // Survives being saved and loaded.
      expect(Track.fromJson(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>).description, t.description);

      final built = groupBooks(tracks).single;
      expect(built.title, 'The Last Kettle');
      expect(built.author, 'Jane Brewer');
      expect(built.narrator, 'Peter Pour, Ann Steep');
      expect(built.seriesLabel, 'The Tea Saga 0.1');
      expect(built.description, startsWith('A kettle'));
      expect(built.chapters.length, 2);
    });
  });

  test('a metadata file marks MP3s as a book even without an audiobook genre', () {
    const t = Track(
      id: 'local:/m/a.mp3',
      source: TrackSource.local,
      title: 'a',
      artist: 'x',
      album: 'y',
      albumArtist: 'x',
      path: '/m/a.mp3',
      hasBookInfo: true,
    );
    expect(BookRules().isBook(t), isTrue);
  });

  test('HTML descriptions become text', () {
    expect(htmlToText('<p>One<br/>Two</p><ul><li>A</li><li>B</li></ul>'), 'One\nTwo\n\n• A\n• B');
    expect(htmlToText('&#8220;Hi&#8221;'), '“Hi”');
  });
}
