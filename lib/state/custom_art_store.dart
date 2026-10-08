// Pictures the user chose (refactor phase 3, 8 Oct 2026; was part of LibraryModel, and a copy in
// VideoLibraryModel). Covers, artist and series pictures (art/custom) and video pictures and
// posters (art/video/custom) are copied into the app's own folder under a name made from their
// contents (md5), so the same picture is kept once and moving or deleting the original doesn't
// break it. Pictures nothing uses any more are deleted.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Tells the screens that a picture file may have changed, so they don't keep showing an old
/// copy. main.dart sets it to clear Flutter's image cache (state/ doesn't draw pictures itself).
void Function() picturesChanged = () {};

/// A folder of pictures the user chose.
class CustomArtStore {
  CustomArtStore(this.dir, {this.protectNew = false});

  /// Where the pictures are kept.
  final String dir;

  /// Keep a newly stored picture from [removeUnused] until something uses it, for at most
  /// [importGrace]. HomeTunes (0.1.16): a cover is copied in when it's picked but only saved into
  /// an edit when the editor's Save is pressed, so any other edit saved in between used to
  /// delete it as unused. (Covers do this; video pictures are used as soon as they're stored.)
  final bool protectNew;
  static const importGrace = Duration(minutes: 30);
  final Map<String, DateTime> _justStored = {};

  /// Copies a picture file in and returns the copy's path.
  Future<String> importFile(String sourcePath) async =>
      store(await File(sourcePath).readAsBytes(), p.extension(sourcePath).toLowerCase());

  /// Saves picture bytes as `<md5><ext>` (".img" with no extension) and returns the path.
  Future<String> store(List<int> bytes, String ext) async {
    final folder = Directory(dir);
    await folder.create(recursive: true);
    final dest = File(p.join(folder.path, '${md5.convert(bytes)}${ext.isEmpty ? '.img' : ext}'));
    if (!await dest.exists()) await dest.writeAsBytes(bytes, flush: true);
    if (protectNew) _justStored[p.normalize(dest.path)] = DateTime.now();
    return dest.path;
  }

  /// Deletes the pictures in [dir] that aren't in [used] (nor newly stored, with [protectNew]).
  /// A file that can't be deleted right now (e.g. in use) is left for next time.
  Future<void> removeUnused(Set<String> used) async {
    final folder = Directory(dir);
    if (!await folder.exists()) return;
    final inUse = {for (final f in used) p.normalize(f)};
    // Protection ends once something uses the picture (from then on the normal rule applies),
    // or after [importGrace] if it's never used.
    final now = DateTime.now();
    _justStored.removeWhere((path, at) => inUse.contains(path) || now.difference(at) > importGrace);
    final keep = {...inUse, ..._justStored.keys};
    await for (final f in folder.list()) {
      if (f is File && !keep.contains(p.normalize(f.path))) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }
}
