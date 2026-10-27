// Pretend downloads for tests (0.2.3): FakeEngine stands in for background_downloader, FakeSources
// for the servers. Used by downloads_test.dart and the Settings pages test.
import 'dart:async';
import 'dart:io' as io;

import 'package:hometunes/models/download.dart';
import 'package:hometunes/services/download_engine.dart';
import 'package:hometunes/state/downloads_model.dart';


/// Stands in for background_downloader: remembers what it was given; [finish] and [fail] say
/// how a download went.
class FakeEngine implements DownloadEngine {
  final _updates = StreamController<EngineUpdate>.broadcast();
  final List<DownloadJob> jobs = [];
  final List<String> cancelled = [], paused = [];
  bool? wifiOnly;

  @override
  Stream<EngineUpdate> get updates => _updates.stream;
  @override
  Future<void> start() async {}
  @override
  Future<bool> enqueue(DownloadJob job) async {
    jobs.add(job);
    return true;
  }

  @override
  Future<bool> pause(String taskId) async {
    paused.add(taskId);
    return true;
  }

  @override
  Future<bool> resume(String taskId) async => true;
  @override
  Future<void> cancel(String taskId) async => cancelled.add(taskId);
  @override
  Future<void> setWifiOnly(bool on) async => wifiOnly = on;
  @override
  Future<bool?> onWifi() async => null;
  @override
  Stream<bool?> get wifiChanges => const Stream.empty();
  @override
  Future<void> askForNotifications() async {}

  DownloadJob jobFor(String id) => jobs.lastWhere((j) => j.taskId == DownloadsModel.taskIdFor(id));

  /// The file arrives ([bytes] of it).
  Future<void> finish(String id, {int bytes = 1000, String? mime}) async {
    final j = jobFor(id);
    io.File(j.path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 7));
    _updates.add(EngineUpdate(j.taskId, status: EngineStatus.done, mimeType: mime));
    await pumpEvents();
  }

  Future<void> fail(String id, {int? http}) async {
    _updates.add(EngineUpdate(jobFor(id).taskId, status: EngineStatus.failed, httpStatus: http));
    await pumpEvents();
  }

  void close() => _updates.close();
}

/// Lets streams and futures run.
Future<void> pumpEvents() async {
  // (Real files are made on the way, so it waits a little, not just a turn.)
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Stands in for the servers: every server video can be fetched.
class FakeSources implements DownloadSources {
  final List<String> asked = [];
  bool up = true;

  @override
  Future<DownloadRequest?> request(DownloadEntry e) async {
    asked.add('${e.id}@${e.quality.code}');
    if (!up) return null;
    return (
      url: 'http://192.168.1.81:8096/Items/${e.id}/Download',
      headers: const {'Authorization': 'MediaBrowser Token="secret"'},
      ext: 'mkv',
      subtitles: const <({String url, String format})>[],
    );
  }

  @override
  String? problem(DownloadEntry e) => 'The server isn\'t on.';
}

