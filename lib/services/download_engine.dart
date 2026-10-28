// What fetches download files (0.2.3, step 3 of the Servers & Downloads plan). DownloadsModel
// (state/downloads_model.dart) decides what to download and keeps the list; a DownloadEngine only
// moves bytes: start a file, pause, resume, cancel, and say how it's going. The app uses
// [BackgroundDownloaderEngine] (the background_downloader package: resumable downloads, at most
// two at a time, Wi-Fi only on Android, and on Android they carry on when HomeTunes is in the
// background or closed, as a WorkManager job with a "Downloading" notification); tests use a fake.
//
// Note: the engine keeps its own small database of tasks, which holds each task's address and
// headers. For a Subsonic song the address carries the sign-in token (as every Subsonic request
// does); for Jellyfin the token is in a header. It's in HomeTunes' own app-data folder, like the
// rest of its data, and never in backups.
import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;

/// One file to fetch.
class DownloadJob {
  /// Unique per download (the engine's task id).
  final String taskId;
  final String url;
  final Map<String, String> headers;

  /// Where it goes: an absolute folder and a file name.
  final String folder;
  final String fileName;

  /// Shown in the phone's notification.
  final String displayName;

  /// A big file (a video): resumable across Android's 9-minute job limit.
  final bool large;

  /// Downloaded because something is kept offline or an episode ahead, rather than asked for.
  final bool automatic;
  const DownloadJob({
    required this.taskId,
    required this.url,
    this.headers = const {},
    required this.folder,
    required this.fileName,
    required this.displayName,
    this.large = false,
    this.automatic = false,
  });

  String get path => p.join(folder, fileName);
}

enum EngineStatus { waiting, running, paused, done, failed, notFound, canceled }

/// How a download is getting on.
class EngineUpdate {
  final String taskId;

  /// Null for a progress-only update.
  final EngineStatus? status;

  /// 0–1 (null when it isn't known).
  final double? progress;

  /// How big the file is, when the server said.
  final int? expectedBytes;

  /// The server's answer, for a finished or failed download.
  final int? httpStatus;
  final String? mimeType;
  final String? error;
  const EngineUpdate(this.taskId,
      {this.status, this.progress, this.expectedBytes, this.httpStatus, this.mimeType, this.error});
}

abstract class DownloadEngine {
  Stream<EngineUpdate> get updates;

  /// Gets going, and replays how downloads started earlier went (e.g. while the app was closed).
  Future<void> start();

  /// Starts (or queues) [job]. False when it couldn't be queued.
  Future<bool> enqueue(DownloadJob job);
  Future<bool> pause(String taskId);
  Future<bool> resume(String taskId);
  Future<void> cancel(String taskId);

  /// Phones and TVs: only download over Wi-Fi.
  Future<void> setWifiOnly(bool on);

  /// Whether this device is on Wi-Fi (null: can't tell, or it doesn't matter here).
  Future<bool?> onWifi();
  Stream<bool?> get wifiChanges;

  /// Asks for permission to show the "Downloading" notification (Android 13+), once.
  Future<void> askForNotifications();
}

/// The real engine.
class BackgroundDownloaderEngine implements DownloadEngine {
  final FileDownloader _fd = FileDownloader();
  final _updates = StreamController<EngineUpdate>.broadcast();
  final Map<String, DownloadTask> _tasks = {};
  StreamSubscription<TaskUpdate>? _sub;
  bool _started = false;

  @override
  Stream<EngineUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _fd.updates.listen(_on);
    await _fd.configure(
      globalConfig: [
        // Two at a time (the holding queue lives on the native side, so on Android the next one
        // starts even while HomeTunes is in the background).
        (Config.holdingQueue, (2, null, null)),
        // Leave at least 500 MB free on the drive.
        (Config.checkAvailableSpace, 500),
      ],
      androidConfig: [
        // A foreground job (with its notification) for anything over 20 MB, so Android doesn't
        // stop it after 9 minutes; big files shouldn't go through the small cache folder.
        (Config.runInForegroundIfFileLargerThan, 20),
        (Config.useCacheDir, Config.never),
      ],
    );
    _fd.configureNotification(
      running: const TaskNotification('Downloading', '{displayName}'),
      paused: const TaskNotification('Download paused', '{displayName}'),
      error: const TaskNotification('Download failed', '{displayName}'),
      progressBar: true,
    );
    await _fd.start(autoCleanDatabase: true);
  }

  @override
  Future<bool> enqueue(DownloadJob job) async {
    final task = DownloadTask(
      taskId: job.taskId,
      url: job.url,
      headers: job.headers,
      baseDirectory: BaseDirectory.root,
      directory: job.folder,
      filename: job.fileName,
      displayName: job.displayName,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
      transferHints: {
        if (!job.automatic) TransferHint.userInitiated,
        if (job.large) TransferHint.largeFile,
        if (job.automatic) TransferHint.lowPriority,
      },
    );
    _tasks[job.taskId] = task;
    return _fd.enqueue(task);
  }

  Future<DownloadTask?> _task(String id) async {
    final known = _tasks[id];
    if (known != null) return known;
    final t = await _fd.taskForId(id);
    return t is DownloadTask ? _tasks[id] = t : null;
  }

  @override
  Future<bool> pause(String taskId) async {
    final t = await _task(taskId);
    return t == null ? false : _fd.pause(t);
  }

  @override
  Future<bool> resume(String taskId) async {
    final t = await _task(taskId);
    return t == null ? false : _fd.resume(t);
  }

  @override
  Future<void> cancel(String taskId) async {
    _tasks.remove(taskId);
    await _fd.cancelTaskWithId(taskId);
  }

  @override
  Future<void> setWifiOnly(bool on) async {
    if (!Platform.isAndroid) return;
    await _fd.requireWiFi(on ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
  }

  @override
  Future<bool?> onWifi() async {
    if (!Platform.isAndroid) return null;
    try {
      return _isWifi(await Connectivity().checkConnectivity());
    } catch (_) {
      return null;
    }
  }

  static bool _isWifi(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);

  @override
  Stream<bool?> get wifiChanges => Platform.isAndroid
      ? Connectivity().onConnectivityChanged.map<bool?>(_isWifi)
      : const Stream<bool?>.empty();

  bool _asked = false;

  @override
  Future<void> askForNotifications() async {
    if (!Platform.isAndroid || _asked) return;
    _asked = true;
    try {
      final status = await _fd.permissions.status(PermissionType.notifications);
      if (status != PermissionStatus.granted) await _fd.permissions.request(PermissionType.notifications);
    } catch (_) {}
  }

  void _on(TaskUpdate u) {
    final id = u.task.taskId;
    switch (u) {
      case TaskStatusUpdate():
        final s = switch (u.status) {
          TaskStatus.enqueued || TaskStatus.waitingToRetry => EngineStatus.waiting,
          TaskStatus.running => EngineStatus.running,
          TaskStatus.paused => EngineStatus.paused,
          TaskStatus.complete => EngineStatus.done,
          TaskStatus.notFound => EngineStatus.notFound,
          TaskStatus.failed => EngineStatus.failed,
          TaskStatus.canceled => EngineStatus.canceled,
        };
        if (u.status.isFinalState) _tasks.remove(id);
        _updates.add(EngineUpdate(id,
            status: s,
            httpStatus: u.responseStatusCode,
            mimeType: u.mimeType,
            error: u.exception?.description));
      case TaskProgressUpdate():
        if (u.progress < 0) return; // a status update says what happened
        _updates.add(EngineUpdate(id, progress: u.progress, expectedBytes: u.hasExpectedFileSize ? u.expectedFileSize : null));
    }
  }

  void dispose() {
    _sub?.cancel();
    _updates.close();
  }
}
