// A playing video's length corrected by the player waits for the next pause or stop before the
// screens are told (0.2.12, VideoLibraryModel.savePlace): the rebuild of every video used to come
// a few seconds into such a video, a hitch on the TV.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';

void main() {
  late Directory dir;
  late VideoLibraryModel videos;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_quiet_length');
    final storage = Storage.at(dir);
    final lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
    videos.setServerVideos('s1', [
      const VideoItem(id: 'jf:s1:a', path: 'jellyfin://s1/a.mkv', title: 'A', collection: 'Show', duration: Duration(minutes: 40)),
    ]);
  });
  tearDown(() async {
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a new length while playing waits for the pause; then every screen has it', () async {
    var told = 0;
    videos.addListener(() => told++);
    videos.savePlace('jf:s1:a', const Duration(seconds: 5), const Duration(minutes: 42), quiet: true);
    videos.savePlace('jf:s1:a', const Duration(seconds: 10), const Duration(minutes: 42), quiet: true);
    expect(told, 0);
    expect(videos.byId('jf:s1:a')!.duration, const Duration(minutes: 40));
    videos.savePlace('jf:s1:a', const Duration(seconds: 12), const Duration(minutes: 42), paused: true);
    expect(told, 1);
    expect(videos.byId('jf:s1:a')!.duration, const Duration(minutes: 42));
  });

  test('when not playing quietly, the new length shows at once, as before', () {
    videos.savePlace('jf:s1:a', const Duration(seconds: 5), const Duration(minutes: 43));
    expect(videos.byId('jf:s1:a')!.duration, const Duration(minutes: 43));
  });
}
