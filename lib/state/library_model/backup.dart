// Part of LibraryModel (refactor phase 10, 9 Oct 2026: library_model.dart was over 1,500 lines).
// Backup and restore, and writing the user's edits into the music files.
part of '../library_model.dart';

extension LibraryBackup on LibraryModel {
  /// Everything HomeTunes keeps on this device, as one file (see [AppBackup]).
  /// The server password is never included (0.1.21, security review #6): it would be readable
  /// by anyone with the file. After restoring on another device it's typed in once.
  Future<Uint8List> createBackup({bool includeCoverCache = true}) =>
      AppBackup.create(storage, includeCoverCache: includeCoverCache);

  /// Where the automatic "just before restoring" backup is kept.
  String get beforeRestorePath => p.join(storage.root.path, AppBackup.beforeRestoreName);

  /// Restores [backup] (replacing or merging, see [AppBackup.restore]), after
  /// saving the current data to [beforeRestorePath]. [reloadOthers] reloads
  /// the other models (playlists). Then rescans, so songs are matched up.
  Future<RestoreResult> restoreBackup(
    BackupContents backup, {
    required bool merge,
    required Future<void> Function() reloadOthers,
  }) async {
    late RestoreResult result;
    await _enqueue(() async {
      error = null;
      status = 'Restoring backup…';
      _changed();
      try {
        // 1. Save everything as it is now, so a bad restore can be undone. (Without the server
        //    password since 0.1.17: it stays in protected storage, so undoing keeps it anyway.)
        final undo = await AppBackup.create(storage);
        await File(beforeRestorePath).writeAsBytes(undo, flush: true);
        // 2. Write the backup's files, then reload this model and the others from them.
        //    (AppBackup.restore throws if a file can't be saved; the error reaches the caller.)
        result = await AppBackup.restore(storage, backup, merge: merge);
        await load();
        await reloadOthers();
        // The same server's password is still in protected storage: no need to type it again.
        if (result.needsPassword && server.password.isNotEmpty) {
          result = RestoreResult(missingFolders: result.missingFolders, needsPassword: false);
        }
      } finally {
        status = null;
      }
    });
    // 3. Rescan (a backup from another computer has different paths) and sync if needed.
    await scanLocal();
    if (_client != null && _remote.isEmpty) await syncServer();
    return result;
  }

  // ---- writing edits into the music files ----

  /// Local songs whose HomeTunes edits could be written into their files.
  List<Track> get tracksWithWritableEdits => [
        for (final t in _local)
          if (_edits.containsKey(t.id) && t.path != null && TagSupport.forPath(t.path!).anything) t,
      ];

  /// Songs with edits that can't go into their files (server songs, OGG/Opus…).
  int get unwritableEditCount =>
      _edits.keys.where(_rawById.containsKey).length - tracksWithWritableEdits.length;

  /// Where copies of files are kept before tags are written into them.
  String get backupRoot => p.join(storage.root.path, 'backups');

  /// Writes the HomeTunes edits of [tracks] into their music files. Anything a
  /// file type can't hold stays as a HomeTunes edit. With [backup], each file
  /// is copied into a dated folder under [backupRoot] first.
  Future<List<TagWriteResult>> writeEditsToFiles(List<Track> tracks, {bool backup = true}) async {
    final results = <TagWriteResult>[];
    // A folder name like 2026-09-25T14-03-11 (":" isn't allowed in Windows file names).
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backupDir = backup ? p.join(backupRoot, stamp) : null;
    await _enqueue(() async {
      error = null;
      var done = 0;
      for (final t in tracks) {
        status = 'Writing tags ${++done} / ${tracks.length}';
        final edit = _edits[t.id];
        if (edit == null || t.path == null) continue;
        final r = await writeTagsToFile(t.path!, edit,
            backupDir: backupDir, libraryRoots: _scanFolders, artRoots: [storage.artDir]);
        results.add(r);
        // Written: whatever the file now holds is no longer needed as an edit; anything the
        // format couldn't hold (the leftover) stays as an edit. A failed write changes nothing.
        if (r.ok) {
          if (r.leftover.isEmpty) {
            _edits.remove(t.id);
          } else {
            _edits[t.id] = r.leftover;
          }
        }
      }
      await storage.write('edits.json', {for (final e in _edits.entries) e.key: e.value.toJson()});
      // Re-read the changed files so the library shows their new tags.
      status = 'Re-reading changed files…';
      _changed();
      final previous = {for (final t in _local) t.id: t};
      _local = await _scanAvailable(previous);
      await _reconcile(previous);
      await _saveLibrary();
      await _removeUnusedCustomArt();
      status = null;
    });
    return results;
  }
}
