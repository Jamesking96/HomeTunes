// A short diary of what the player did: songs opening, playing and pausing, the app going to
// the background and back, what the phone's media controls were told, and any problem the
// player noticed and fixed (like playback that stopped by itself). The last few hundred lines
// are kept in playback-log.txt in the data folder, so after something odd happens on the phone
// the log can be read in Settings › About, or copied and sent. Not included in backups.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class PlaybackLog {
  PlaybackLog._();

  /// How many lines are kept.
  static const maxLines = 400;

  static final List<String> _lines = [];
  static File? _file;
  static Timer? _saveTimer;

  /// The lines, oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  /// Starts keeping the log in [dataFolder], carrying on from the last run's lines.
  static Future<void> attach(String dataFolder) async {
    final f = File(p.join(dataFolder, 'playback-log.txt'));
    _file = f;
    try {
      if (await f.exists()) {
        final old = await f.readAsLines();
        _lines.insertAll(0, old.length > maxLines ? old.sublist(old.length - maxLines) : old);
        _trim();
      }
    } catch (_) {
      // An unreadable log just starts again.
    }
  }

  /// Adds a line (also printed to the debug console / Android log).
  static void add(String message, {DateTime? at}) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final line = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $message';
    _lines.add(line);
    _trim();
    debugPrint('HomeTunes: $message');
    _saveSoon();
  }

  /// Empties the log (for tests, or "Clear" in Settings).
  static void clear() {
    _lines.clear();
    _saveSoon();
  }

  static void _trim() {
    if (_lines.length > maxLines) _lines.removeRange(0, _lines.length - maxLines);
  }

  static void _saveSoon() {
    if (_file == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), save);
  }

  /// Writes the log now.
  static Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString('${_lines.join('\n')}\n', flush: true);
    } catch (_) {
      // Best effort: a log that can't be saved mustn't get in the way of playing.
    }
  }

  /// For tests: forget the file and the lines.
  @visibleForTesting
  static void reset() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _file = null;
    _lines.clear();
  }
}
