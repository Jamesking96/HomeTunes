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

LocalLyrics readLocalLyricsNow(String path) {
  String? tags;
  try {
    tags = _clean(readMetadata(File(path), getImage: false).lyrics);
  } catch (_) {
    // Unreadable tags: the .lrc file may still be there.
  }
  return (tags: tags, lrc: _clean(readTextFile(lrcPathFor(path))));
}

/// The `.lrc` file for a song (same folder and name), whatever case its
/// extension is in. Null if there isn't one.
String? lrcPathFor(String songPath) {
  final base = p.join(p.dirname(songPath), p.basenameWithoutExtension(songPath));
  for (final ext in const ['.lrc', '.LRC', '.Lrc']) {
    if (File('$base$ext').existsSync()) return '$base$ext';
  }
  return null;
}

/// A text file as UTF-8 (or Latin-1 if it isn't valid UTF-8), without a BOM.
String? readTextFile(String? path) {
  if (path == null) return null;
  try {
    final bytes = File(path).readAsBytesSync();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return text.startsWith('﻿') ? text.substring(1) : text;
  } catch (_) {
    return null;
  }
}

String? _clean(String? s) => (s == null || s.trim().isEmpty) ? null : s;
