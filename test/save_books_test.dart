// Saving audiobooks into your own folders (5 Nov 2026, the user: "Give me the ability to download
// the audiobooks to save them locally"): DownloadsModel.saveBook downloads a server book's files
// that aren't here, then copies the book into Author / Series / n - Title with its cover and an
// Audiobookshelf metadata.json, rescans, and moves the listening place across.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/book.dart';
import 'package:hometunes/models/download.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/services/book_sidecar.dart';
import 'package:hometunes/services/music_permission.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/downloads_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:path/path.dart' as p;

import 'fake_download_engine.dart';

/// The servers, with books' files as MP3s.
class _BookSources extends FakeSources {
  @override
  Future<DownloadRequest?> request(DownloadEntry e) async => (
        url: 'http://192.168.0.10:13378/api/items/${e.id}/download',
        headers: const {'Authorization': 'Bearer secret'},
        ext: 'mp3',
        subtitles: const <({String url, String format})>[],
        hls: false,
      );
}

void main() {
  late Directory dir;
  late String root;
  late Storage storage;
  late LibraryModel lib;
  late ListeningModel listening;
  late VideoLibraryModel videos;
  late FakeEngine engine;
  late DownloadsModel dl;

  Track part(int n, String title, String cover) => Track(
        id: 'abs:abs1:item1:$n',
        source: TrackSource.server,
        title: title,
        artist: 'Terry Pratchett',
        album: 'The Colour of Magic',
        albumArtist: 'Terry Pratchett',
        trackNumber: n,
        year: 1983,
        genre: 'Fantasy',
        duration: const Duration(minutes: 40),
        narrator: 'Nigel Planer',
        series: 'Discworld',
        seriesIndex: 1,
        description: 'Rincewind meets Twoflower.',
        hasBookInfo: true,
        art: cover,
      );

  Future<DownloadsModel> makeModel() async {
    final m = DownloadsModel(
      storage: storage,
      library: lib,
      playlists: PlaylistsModel(storage),
      videos: videos,
      engine: engine,
      sources: _BookSources(),
      listening: listening,
    );
    await m.load();
    await m.start();
    return m;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_save_books');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync(recursive: true);
    root = p.join(dir.path, 'Audiobooks');
    Directory(root).createSync();
    lib = LibraryModel(storage)..checkAccess = () async => MusicAccess.allowed;
    lib.audiobookFolders = [root];
    final cover = p.join(storage.artDir, 'item1.jpg');
    File(cover).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    lib.setServerBookTracks('abs1', [part(1, 'Part One', cover), part(2, 'Part Two', cover)]);
    listening = ListeningModel(storage);
    videos = VideoLibraryModel(storage, lib);
    engine = FakeEngine();
    dl = await makeModel();
  });

  tearDown(() async {
    dl.dispose();
    engine.close();
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Book server() => lib.books.firstWhere((b) => b.id == 'book:abs:abs1:item1');

  test('the folder and metadata.json a book is saved with', () {
    final b = server();
    expect(SaveBooks.bookFolderNames(b), ['Terry Pratchett', 'Discworld', '1 - The Colour of Magic']);
    final info = BookInfo.parse(jsonEncode(SaveBooks.bookMetadata(b)))!;
    expect((info.title, info.series, info.seriesIndex, info.year), ('The Colour of Magic', 'Discworld', 1.0, 1983));
    expect(info.authors, ['Terry Pratchett']);
    expect(info.narrators, ['Nigel Planer']);
    expect(info.genres, ['Fantasy']);
    expect(info.description, 'Rincewind meets Twoflower.');
  });

  test('Save to my audiobooks: downloads the book, then saves it whole with its place', () async {
    final b = server();
    await listening.record(b, 'abs:abs1:item1:2', const Duration(minutes: 1, seconds: 23));
    expect(await dl.saveBook(b, root), isNull); // not here yet: downloading
    expect(dl.isSavingBook(b.id), isTrue);
    expect(dl.savingBookTo(b.id), root);
    expect(dl.isPending('abs:abs1:item1:1') && dl.isPending('abs:abs1:item1:2'), isTrue);

    // Waiting is remembered across a restart.
    dl.dispose();
    dl = await makeModel();
    expect(dl.isSavingBook(b.id), isTrue);

    await engine.finish('abs:abs1:item1:1');
    expect(dl.isSavingBook(b.id), isTrue); // one of two
    final notices = <String>[];
    dl.onNotice = notices.add;
    await engine.finish('abs:abs1:item1:2');
    for (var i = 0; i < 50 && dl.isSavingBook(b.id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final folder = p.join(root, 'Terry Pratchett', 'Discworld', '1 - The Colour of Magic');
    expect(dl.isSavingBook(b.id), isFalse);
    expect(notices.single, contains('is saved in'));
    expect({for (final f in Directory(folder).listSync()) p.basename(f.path)},
        {'01 - Part One.mp3', '02 - Part Two.mp3', 'cover.jpg', 'metadata.json'});
    // The downloads went: the files are yours now.
    expect(dl.entryOf('abs:abs1:item1:1'), isNull);
    expect(dl.entryOf('abs:abs1:item1:2'), isNull);

    // The saved copy is a book of your own, and carries on in Part Two at 1:23.
    final mine = lib.books.firstWhere((x) => x.parts.any((t) => t.path != null && p.isWithin(folder, t.path!)));
    expect(mine.title, 'The Colour of Magic');
    expect(mine.parts, hasLength(2));
    final place = listening.progressFor(mine)!;
    expect(p.basename(lib.byId(place.partId)!.path!), '02 - Part Two.mp3');
    expect(place.position, const Duration(minutes: 1, seconds: 23));

    // Saving it again goes in a folder of its own.
    await dl.saveBook(b, root);
    await pumpEvents(); // handed to the engine
    for (final id in ['abs:abs1:item1:1', 'abs:abs1:item1:2']) {
      await engine.finish(id);
    }
    for (var i = 0; i < 50 && dl.isSavingBook(b.id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(Directory('$folder (2)').existsSync(), isTrue);
  });

  test('a book already downloaded is saved straight away; Stop saving leaves its downloads', () async {
    final b = server();
    dl.download([for (final t in b.parts) DownloadItem.track(t, book: true)], const DownloadQuality.original());
    await pumpEvents(); // handed to the engine
    await engine.finish('abs:abs1:item1:1');
    expect(await dl.saveBook(b, root), isNull);
    await dl.cancelSaveBook(b.id);
    expect(dl.isSavingBook(b.id), isFalse);
    await engine.finish('abs:abs1:item1:2');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(Directory(p.join(root, 'Terry Pratchett')).existsSync(), isFalse); // not saved
    expect(dl.isDownloaded('abs:abs1:item1:2'), isTrue);

    final to = await dl.saveBook(b, root);
    expect(to, p.join(root, 'Terry Pratchett', 'Discworld', '1 - The Colour of Magic'));
    expect(File(p.join(to!, '01 - Part One.mp3')).existsSync(), isTrue);
  });
}
