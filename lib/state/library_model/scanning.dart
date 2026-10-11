// Part of LibraryModel (refactor phase 10, 9 Oct 2026: library_model.dart was over 1,500 lines).
// Scanning: every folder or one, one job at a time, leaving out folders that are offline (a drive
// not plugged in) rather than forgetting their songs.
part of '../library_model.dart';

extension LibraryScanning on LibraryModel {
  /// Rescans just [folder] (its options window). Songs elsewhere are left as they are.
  Future<void> scanFolder(String folder) => _enqueue(() async {
        musicAccess = await checkAccess();
        if (musicAccess != MusicAccess.allowed) {
          error = LibraryModel._noAccessMessage;
          return;
        }
        if (!await folderReachable(folder)) {
          error = 'Can\'t reach $folder right now, so what was found there before is kept.';
          return;
        }
        error = null;
        final name = p.basename(folder);
        status = 'Scanning $name…';
        _changed();
        _applyPendingDurations();
        try {
          final previous = {for (final t in _local) t.id: t};
          final scanned = await _scanner.scan([folder], previous: previous, onProgress: (done, total) {
            status = 'Scanning $name: $done / $total';
          });
          final found = {for (final t in scanned) t.id};
          // Everything outside the folder stays; everything inside comes from this scan.
          _local = [
            for (final t in _local)
              if (!found.contains(t.id) && !(t.path != null && isInside(t.path!, folder))) t,
            ...scanned,
          ]..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
          offlineFolders = [for (final f in offlineFolders) if (f != folder) f];
          await _reconcile(previous);
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

  /// Runs [work] after any job already running or waiting. Each job is chained onto the
  /// previous one, so they queue up. The library is rebuilt once each job finishes.
  Future<void> _enqueue(Future<void> Function() work) {
    _queued++;
    final next = _jobs.then((_) async {
      busy = true;
      _changed();
      try {
        await work();
      } finally {
        _queued--;
        busy = _queued > 0;
        _rebuild();
      }
    });
    // The chain swallows errors so one failed job doesn't block the ones after it, but the
    // caller still gets the error through `next`.
    _jobs = next.catchError((_) {});
    return next;
  }

  Future<void> scanLocal() => _enqueue(() async {
        // Without access the scan would find nothing and wrongly drop every
        // song from the library, so don't scan at all.
        musicAccess = await checkAccess();
        if (musicAccess != MusicAccess.allowed && _scanFolders.isNotEmpty) {
          error = LibraryModel._noAccessMessage;
          return;
        }
        error = null;
        status = 'Looking for music…';
        _changed();
        // Lengths learned while playing go in first, so the scan keeps them.
        _applyPendingDurations();
        try {
          // Give the scanner what we already know, so unchanged files are reused, not re-read.
          final previous = {for (final t in _local) t.id: t};
          // Progress goes into statusText only (no notifyListeners), so the app isn't redrawn.
          _local = await _scanAvailable(previous, onProgress: (done, total) {
            status = 'Scanning $done / $total';
          });
          // Follow moved files and keep gone ones that matter, save, then tidy unused covers.
          await _reconcile(previous);
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
          if (offlineFolders.isNotEmpty) error = _offlineMessage();
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

  /// Scans the folders that can be reached. Songs in folders that can't be reached are kept
  /// exactly as they were in [previous], instead of counting as gone.
  ///
  /// HomeTunes (0.1.16): before, an unplugged drive looked like an empty folder, so its songs
  /// were dropped (all but those with edits or playlist places), their cached covers deleted,
  /// and everything read again from scratch when the drive came back.
  Future<List<Track>> _scanAvailable(Map<String, Track> previous, {void Function(int done, int total)? onProgress}) async {
    // A missing folder inside one that can be reached has really gone (its drive is there).
    final (:reachable, :offline) = await checkFolders(_scanFolders, folderReachable);
    offlineFolders = offline;
    final scanned = await _scanner.scan(reachable, previous: previous, onProgress: onProgress);
    if (offlineFolders.isEmpty) return scanned;
    final found = {for (final t in scanned) t.id};
    final kept = [
      for (final t in previous.values)
        if (!found.contains(t.id) && t.path != null && offlineFolders.any((f) => isInside(t.path!, f))) t,
    ];
    // Same order as a normal scan: by path.
    return [...scanned, ...kept]..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
  }

  String _offlineMessage() {
    final names = offlineFolders.join(', ');
    return offlineFolders.length == 1
        ? 'Can\'t reach $names right now, so its songs are shown as they were. '
            'If it\'s gone for good, remove it in Settings.'
        : 'Can\'t reach $names right now, so their songs are shown as they were. '
            'If they\'re gone for good, remove them in Settings.';
  }

  // ---- server ----
}
