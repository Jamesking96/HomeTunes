// Checks a file path before HomeTunes hands it to something that acts on it: opening a book's PDF
// in the computer's own app, showing a file in Explorer, reading a cover into a music file's tags,
// or writing tags into a music file.
//
// HomeTunes (0.1.21, security review #3): paths reach the app from scans, but also from a restored
// .htbackup, which is just a file someone could have edited. Before this, a crafted backup could
// make "Open PDF" run a program (explorer.exe opens whatever it is given), reach out to a network
// share (which also sends the Windows login hash), or pull any file on the PC into a song's tags.
// Now a path is only used when it's a real file inside one of the user's library folders or the
// app's own art folder, with the kind of extension the action expects.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../state/book_index.dart' show isInside;

/// True when [path] is safe for HomeTunes to act on:
///  * absolute, with no "." or ".." tricks left after normalising;
///  * inside one of [roots] (the library folders, plus the app's art folder where that applies);
///  * when [extensions] is given, its extension (lower case, with the dot) is one of them;
///  * it exists and is a file (not a folder).
///
/// The roots are checked before the disk is touched, so a path outside them never causes a
/// network lookup. Network paths (\\server\share\…) only pass when a library folder is itself
/// on that share.
bool isUsableLocalFile(String path, {required Iterable<String> roots, Set<String>? extensions}) {
  if (!isInsideAny(path, roots)) return false;
  final norm = p.normalize(path);
  if (extensions != null && !extensions.contains(p.extension(norm).toLowerCase())) return false;
  try {
    return FileSystemEntity.typeSync(norm, followLinks: true) == FileSystemEntityType.file;
  } catch (_) {
    return false;
  }
}

/// True when [path] is an absolute path inside one of [roots]. Only looks at the text of the
/// paths, never at the disk, so it's cheap enough for every cover shown on screen, and a path
/// outside the roots (say, on a network share) is never looked up.
bool isInsideAny(String path, Iterable<String> roots) {
  if (path.trim().isEmpty || !p.isAbsolute(path)) return false;
  final norm = p.normalize(path);
  if (p.split(norm).contains('..')) return false;
  return roots.any((r) => r.trim().isNotEmpty && p.isAbsolute(r) && isInside(norm, p.normalize(r)));
}
