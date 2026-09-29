// Checking for a newer HomeTunes, and updating to it (0.1.23).
//
// Settings › About shows [stage] and has "Check for updates"; main.dart calls [checkIfDue] a
// little after start-up so a new version is noticed at most once a day (unless the user turns
// [autoCheck] off). The work itself is in services/update_checker.dart. Its own small file,
// updates.json, holds the switch and when the last check ran; it isn't part of backups, since
// it belongs to this device.
import 'package:flutter/foundation.dart';

import '../services/storage.dart';
import '../services/update_checker.dart';

/// Where the update check has got to.
enum UpdateStage { idle, checking, upToDate, available, downloading, installing, failed }

class UpdateModel extends ChangeNotifier {
  final Storage storage;
  final UpdateChecker checker;

  /// This copy's version ("0.1.23"); read by [load].
  final Future<String?> Function() readVersion;

  /// "Now", swappable in tests.
  DateTime Function() now = DateTime.now;

  UpdateModel(this.storage, {UpdateChecker? checker, required this.readVersion})
      : checker = checker ?? UpdateChecker();

  static const file = 'updates.json';

  /// How often the quiet check at start-up runs.
  static const checkEvery = Duration(hours: 24);

  /// Look for updates by itself (at most once a day).
  bool autoCheck = true;

  /// When the last check finished without an error.
  DateTime? lastCheck;

  String? currentVersion;
  UpdateStage stage = UpdateStage.idle;

  /// The newest release, once a check has found one.
  ReleaseInfo? latest;

  /// Download progress 0–1 (null while unknown).
  double? progress;

  /// What went wrong, in plain words, when [stage] is failed.
  String? error;

  bool get busy =>
      stage == UpdateStage.checking || stage == UpdateStage.downloading || stage == UpdateStage.installing;

  /// Whether this copy can download and install the update itself (Windows, installed copy).
  bool get canInstallHere => UpdateChecker.canInstallHere;

  Future<void> load() async {
    try {
      currentVersion = await readVersion();
    } catch (_) {
      currentVersion = null;
    }
    final raw = await storage.read(file);
    if (raw is Map<String, dynamic>) {
      final a = raw['autoCheck'];
      if (a is bool) autoCheck = a;
      final l = raw['lastCheck'];
      if (l is String) lastCheck = DateTime.tryParse(l);
    }
    notifyListeners();
  }

  Future<void> _save() => storage.write(file, {
        'autoCheck': autoCheck,
        if (lastCheck != null) 'lastCheck': lastCheck!.toIso8601String(),
      });

  Future<void> setAutoCheck(bool on) async {
    autoCheck = on;
    notifyListeners();
    await _save();
  }

  /// True when the quiet start-up check should run now.
  bool get isDue {
    if (!autoCheck) return false;
    final last = lastCheck;
    if (last == null) return true;
    final since = now().difference(last);
    return since.isNegative || since >= checkEvery; // a clock moved backwards counts as due
  }

  /// Looks for a newer version. [quiet] (the start-up check) doesn't show "Checking…" or an
  /// error on the About page if it fails. Returns the new release, or null.
  Future<ReleaseInfo?> check({bool quiet = false}) async {
    if (busy) return null;
    final current = currentVersion;
    if (!quiet) {
      stage = UpdateStage.checking;
      error = null;
      notifyListeners();
    }
    try {
      final info = await checker.fetchLatest();
      latest = info;
      lastCheck = now();
      await _save();
      final newer = current != null && isNewerVersion(info.version, current);
      stage = newer ? UpdateStage.available : UpdateStage.upToDate;
      notifyListeners();
      return newer ? info : null;
    } on UpdateException catch (e) {
      if (!quiet) {
        stage = UpdateStage.failed;
        error = e.message;
        notifyListeners();
      }
      return null;
    }
  }

  /// The start-up check: runs only when [isDue]. Returns a newer release if there is one.
  Future<ReleaseInfo?> checkIfDue() => isDue ? check(quiet: true) : Future.value(null);

  /// Windows (installed copy): downloads and checks the installer, then starts it. Returns
  /// true when the installer is running and HomeTunes should close now.
  Future<bool> downloadAndInstall() async {
    final release = latest;
    if (release == null || busy || !canInstallHere) return false;
    stage = UpdateStage.downloading;
    progress = null;
    error = null;
    notifyListeners();
    try {
      final installer = await checker.downloadInstaller(release, onProgress: (f) {
        progress = f;
        notifyListeners();
      });
      stage = UpdateStage.installing;
      notifyListeners();
      await UpdateChecker.startInstaller(installer);
      return true;
    } on UpdateException catch (e) {
      stage = UpdateStage.failed;
      error = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      stage = UpdateStage.failed;
      error = 'The installer couldn\'t be started ($e).';
      notifyListeners();
      return false;
    }
  }

  /// Opens the release page (or the list of releases) in the browser.
  Future<bool> openDownloadPage() => UpdateChecker.openInBrowser(latest?.page ?? releasesPage);
}
