// Checks HomeTunes' Audiobookshelf code against a real server (0.2.7), with the app's own models
// and its data in a temp folder (the real app isn't touched).
// Run: flutter test tool/bench/abs_live_test.dart --dart-define=ABS_URL=http://192.168.1.81:13378
//        --dart-define=ABS_USER=test --dart-define=ABS_PASSWORD=...
//
// Kept in tool/bench/ so the normal test run skips it. It reads the whole server into the Books
// tab, prints what it found (books, files, chapters, covers, places), checks a file streams from
// the address the player would use and downloads from the download address, renews the sign-in
// with the refresh token, and signs out at the end. It never changes a place on the server.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/secret_store.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/server_books.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Audiobookshelf, live', () async {
    const url = String.fromEnvironment('ABS_URL'), user = String.fromEnvironment('ABS_USER');
    const password = String.fromEnvironment('ABS_PASSWORD');
    if (url.isEmpty || user.isEmpty) {
      markTestSkipped('Give ABS_URL, ABS_USER and ABS_PASSWORD with --dart-define.');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('hometunes_abs_live');
    final storage = Storage.at(dir);
    Directory(storage.artDir).createSync(recursive: true);
    final secrets = MemorySecretStore();
    final lib = LibraryModel(storage, secrets: secrets);
    final listening = ListeningModel(storage);
    final servers = ServersModel(storage, lib);
    final entry = await servers.add(
      type: ServerType.audiobookshelf,
      name: 'Live',
      url: url,
      username: user,
      password: password,
      uses: {MediaKind.audiobooks},
    );
    final model = ServerBooksModel(storage: storage, servers: servers, library: lib, listening: listening, secrets: secrets);
    // Never send a place to the real server from here.
    listening.onPlaceSaved = null;
    final watch = Stopwatch()..start();
    await model.sync(entry);
    print('Read in ${watch.elapsedMilliseconds} ms: ${model.statusFor(entry)}');
    expect(model.okFor(entry), isTrue, reason: model.statusFor(entry));
    final books = lib.books;
    print('${books.length} books, ${books.fold<int>(0, (n, b) => n + b.parts.length)} files, '
        '${books.where((b) => b.parts.length > 1).length} in several files');
    for (final b in books.take(12)) {
      print('  ${b.title} — ${b.author}${b.narrator == null ? '' : ', read by ${b.narrator}'}'
          '${b.series == null ? '' : ' [${b.series} #${b.seriesIndex ?? '?'}]'}'
          ' · ${b.parts.length} file(s), ${b.chapters.length} chapters, ${b.duration.inMinutes} min'
          '${listening.progressFor(b) == null ? '' : ' · place ${listening.progressFor(b)!.position.inSeconds} s'}');
    }
    expect(books, isNotEmpty);
    expect(books.every((b) => b.duration > Duration.zero), isTrue);

    // Covers arrive in the background.
    for (var i = 0; i < 600 && books.isNotEmpty && lib.books.where((b) => b.artTrack?.art != null).length < books.length ~/ 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    print('${lib.books.where((b) => b.artTrack?.art != null).length} books have covers');

    // The address the player opens, and the one downloads use.
    final t = lib.books.first.parts.first;
    await model.prepare(t);
    final stream = lib.playableUri(t)!;
    final client = http.Client();
    final r1 = await client.send(http.Request('GET', Uri.parse(stream))..headers['Range'] = 'bytes=0-99');
    print('Stream: ${r1.statusCode} ${r1.headers['content-type']}');
    expect(r1.statusCode, anyOf(200, 206));
    final dl = (await model.downloadRequest(t))!;
    final r2 = await client.send(http.Request('GET', Uri.parse(dl.url))
      ..headers.addAll(dl.headers)
      ..headers['Range'] = 'bytes=0-99');
    print('Download: ${r2.statusCode} ${r2.headers['content-type']} (.${dl.ext})');
    expect(r2.statusCode, anyOf(200, 206));
    client.close();

    // A second read renews nothing it doesn't need to and reads no unchanged book again.
    watch.reset();
    await model.sync(entry);
    print('Read again in ${watch.elapsedMilliseconds} ms');

    await model.signOut(entry);
    model.dispose();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 10)));
}
