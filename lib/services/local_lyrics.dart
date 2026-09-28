// Finds the lyrics that live with a local music file: inside its tags, or in a matching .lrc
// file beside it. LyricsModel (state/lyrics_model.dart) calls readLocalLyrics when it needs a
// song's lyrics (and remembers the answer), then decides which lyrics to show.
// The reading happens in a background isolate so a slow disk never makes the app stutter.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

/// Lyrics kept with a music file: in its tags, and in a `.lrc` file with
/// the same name next to it. Either can be null.
typedef LocalLyrics = ({String? tags, String? lrc});

/// Reads a song's own lyrics (in the background).
Future<LocalLyrics> readLocalLyrics(String path) => Isolate.run(() => readLocalLyricsNow(path));

/// The same, but on the current thread (used inside the isolate, and by tests).
LocalLyrics readLocalLyricsNow(String path) {
  String? tags;
  try {
    tags = _clean(readMetadata(File(path), getImage: false).lyrics);  // skip the cover: faster
  } catch (_) {
    // Unreadable tags: the .lrc file may still be there.
  }
  return (tags: tags, lrc: _clean(readTextFile(lrcPathFor(path))));
}

/// The `.lrc` file for a song (same folder and name), whatever case its
/// extension is in. Null if there isn't one.
String? lrcPathFor(String songPath) {
  final base = p.join(p.dirname(songPath), p.basenameWithoutExtension(songPath));
  // Windows ignores case anyway, but Android's file system doesn't, so try common spellings.
  for (final ext in const ['.lrc', '.LRC', '.Lrc']) {
    if (File('$base$ext').existsSync()) return '$base$ext';
  }
  return null;
}

/// The largest lyrics file read. Real .lrc files are a few KB; a bigger one is ignored rather
/// than read into memory whole (0.1.21, security review #7).
const maxLyricsFileBytes = 1 << 20;

/// A text file as UTF-8 (or Latin-1 if it isn't valid UTF-8), without a BOM. Null if it's
/// missing, unreadable or bigger than [maxBytes].
String? readTextFile(String? path, {int maxBytes = maxLyricsFileBytes}) {
  if (path == null) return null;
  try {
    final file = File(path);
    if (file.lengthSync() > maxBytes) return null;
    final bytes = file.readAsBytesSync();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);  // older Windows-made .lrc files
    }
    // Some editors put an invisible "byte order mark" at the start; drop it.
    return text.startsWith('﻿') ? text.substring(1) : text;
  } catch (_) {
    return null;
  }
}

/// Blank lyrics count as none.
String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s;
