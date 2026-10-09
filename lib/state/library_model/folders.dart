// Part of LibraryModel (refactor phase 10, 9 Oct 2026: library_model.dart was over 1,500 lines).
// The music, audiobook and video folders, each folder's file types (Settings › Folders & scanning), the
// genres that make a file an audiobook, and "Move to Books / Music".
part of '../library_model.dart';

extension LibraryFolders on LibraryModel {
  /// Adds a folder where everything is an audiobook, and scans it.
  Future<void> addAudiobookFolder(String path) async {
    if (audiobookFolders.contains(path)) return;
    audiobookFolders = [...audiobookFolders, path];
    await _saveSettings();
    _changed();
    await scanLocal();
  }

  /// Stops scanning an audiobook folder. The rescan drops its files from the library.
  Future<void> removeAudiobookFolder(String path) async {
    audiobookFolders = audiobookFolders.where((f) => f != path).toList();
    hiddenFormats = {...hiddenFormats}..remove(path);
    await _saveSettings();
    await scanLocal();
  }

  /// Sets which genres count as audiobooks (blank entries are dropped).
  Future<void> setBookGenres(List<String> genres) async {
    bookGenres = [for (final g in genres) if (g.trim().isNotEmpty) g.trim()];
    await _saveSettings();
    _rebuild();
  }

  /// Adds a folder for the Videos tab. VideoLibraryModel notices and scans it.
  Future<void> addVideoFolder(String path) async {
    if (videoFolders.contains(path)) return;
    videoFolders = [...videoFolders, path];
    await _saveSettings();
    _rebuild();
  }

  /// Stops listing a video folder's videos.
  Future<void> removeVideoFolder(String path) async {
    videoFolders = videoFolders.where((f) => f != path).toList();
    hiddenFormats = {...hiddenFormats}..remove(path);
    await _saveSettings();
    _rebuild();
  }

  /// A song file that's really a video in a video folder (an .mp4 on its own there).
  bool _isVideoFolderFile(Track t) {
    final path = t.path;
    if (videoFolders.isEmpty || !t.isLocal || path == null) return false;
    return videoExtensions.contains(p.extension(path).toLowerCase()) && videoFolders.any((f) => isInside(path, f));
  }

  // ---- folders ----

  /// Adds a music folder and scans it.
  Future<void> addFolder(String path) async {
    if (folders.contains(path)) return;
    folders = [...folders, path];
    await _saveSettings();
    _changed();
    await scanLocal();
  }

  /// Stops scanning a music folder. The rescan drops its songs (or keeps them as "missing" if
  /// they're in a playlist or have edits).
  Future<void> removeFolder(String path) async {
    folders = folders.where((f) => f != path).toList();
    hiddenFormats = {...hiddenFormats}..remove(path);
    await _saveSettings();
    await scanLocal();
  }

  // ---- one folder's options (Settings › Folders & scanning, 0.1.27) ----

  // File types switched off per folder (folder path → extensions, lower case without the dot,
  // "wav"): [hiddenFormats], with the folders above. Anything not listed shows, so a type that
  // turns up later shows until switched off.

  /// The folder whose options apply to a file: the innermost music or audiobook folder that
  /// holds it (an audiobook folder inside a music folder has its own options).
  String? ownerFolder(String path) => owningFolder(path, _scanFolders);

  bool _formatHidden(Track t) {
    final path = t.path;
    if (!t.isLocal || path == null) return false;
    final owner = ownerFolder(path);
    return owner != null && (hiddenFormats[owner]?.contains(LibraryModel.formatOf(path)) ?? false);
  }

  /// The file types found in [folder] at the last scan (switched off ones included), with how
  /// many files of each, A–Z.
  Map<String, int> formatsIn(String folder) =>
      formatCounts([for (final t in _local) ?t.path], folder, _scanFolders);

  /// Whether files of [format] in [folder] are shown.
  bool formatShown(String folder, String format) => !(hiddenFormats[folder]?.contains(format) ?? false);

  /// Switches one file type in one folder on or off. Takes effect at once (no rescan needed).
  Future<void> setFormatShown(String folder, String format, bool shown) async {
    final set = {...?hiddenFormats[folder]};
    shown ? set.remove(format) : set.add(format);
    hiddenFormats = {...hiddenFormats};
    if (set.isEmpty) {
      hiddenFormats.remove(folder);
    } else {
      hiddenFormats[folder] = set.toList()..sort();
    }
    _rebuild(); // the screens change at once; the settings file is saved after
    await _saveSettings();
  }

  /// "Move to Books" (true), "Move to Music" (false), or back to automatic (null).
  Future<void> setIsBook(Iterable<String> trackIds, bool? isBook) async {
    for (final id in trackIds) {
      if (isBook == null) {
        _kindOverrides.remove(id);
      } else {
        _kindOverrides[id] = isBook;
      }
    }
    await _saveSettings();
    _rebuild();
  }

  // ---- video folders (0.1.40) ----
}
