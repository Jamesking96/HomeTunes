/// Where a song's lyrics came from.
enum LyricsSource {
  /// Chosen or typed by the user (a HomeTunes edit).
  yours,

  /// The music file's own tags.
  file,

  /// A `.lrc` file next to the song.
  lrcFile,

  /// The Subsonic server.
  server,

  /// Found online on LRCLIB.
  lrclib;

  String get label => switch (this) {
        yours => 'Your lyrics',
        file => 'From the music file',
        lrcFile => 'From the .lrc file',
        server => 'From your server',
        lrclib => 'From LRCLIB',
      };
}

/// One line of lyrics. [time] is set for timed (synced) lyrics.
class LyricLine {
  final Duration? time;
  final String text;
  const LyricLine(this.text, [this.time]);

  @override
  bool operator ==(Object other) => other is LyricLine && other.text == text && other.time == time;

  @override
  int get hashCode => Object.hash(text, time);

  @override
  String toString() => time == null ? text : '[${formatLrcTime(time!)}]$text';
}

/// A song's lyrics: plain text, or timed LRC lines that follow the song.
class Lyrics {
  /// Exactly as stored (plain text or LRC).
  final String text;
  final LyricsSource source;
  final List<LyricLine> lines;

  Lyrics._(this.text, this.source, this.lines);

  factory Lyrics(String text, LyricsSource source) => Lyrics._(text, source, parseLyrics(text));

  /// Timed lyrics highlight the current line and scroll with the song.
  bool get timed => lines.isNotEmpty && lines.first.time != null;

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);

  /// The line being sung at [position], or -1 before the first line.
  int lineAt(Duration position) => lyricLineAt(lines, position);
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _metaTag = RegExp(r'^\[([a-zA-Z#]+):(.*)\]\s*$');
final _wordTag = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');

/// Parses lyrics: LRC (`[01:23.45]words`) if any line has a time, plain
/// text otherwise. LRC tags like `[ar:...]` are dropped, `[offset:+/-ms]` is
/// applied, word timings (`<01:23.45>`) are removed, and lines with several
/// times are repeated at each of them. Timed lines come back in time order.
List<LyricLine> parseLyrics(String text) {
  final rawLines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final hasTimes = rawLines.any((l) => _timeTag.hasMatch(l.trimLeft()) && l.trimLeft().startsWith('['));
  if (!hasTimes) {
    // Plain lyrics: keep the lines (and blank lines between verses), trimmed at the ends.
    final lines = [for (final l in rawLines) LyricLine(l.trimRight())];
    while (lines.isNotEmpty && lines.first.text.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.text.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  var offset = Duration.zero;
  final timed = <LyricLine>[];
  for (final raw in rawLines) {
    var line = raw.trim();
    final meta = _metaTag.firstMatch(line);
    if (meta != null && !_timeTag.hasMatch(line)) {
      if (meta.group(1)!.toLowerCase() == 'offset') {
        final ms = int.tryParse(meta.group(2)!.trim().replaceAll('+', ''));
        // A positive offset makes the lyrics come sooner.
        if (ms != null) offset = Duration(milliseconds: -ms);
      }
      continue;
    }
    final times = <Duration>[];
    while (true) {
      final m = _timeTag.matchAsPrefix(line);
      if (m == null) break;
      times.add(_lrcDuration(m));
      line = line.substring(m.end).trimLeft();
    }
    if (times.isEmpty) continue; // untimed text inside timed lyrics
    final words = line.replaceAll(_wordTag, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final t in times) {
      timed.add(LyricLine(words, t));
    }
  }
  final shifted = [
    for (final l in timed)
      LyricLine(l.text, offset == Duration.zero ? l.time : _atLeastZero(l.time! + offset)),
  ];
  // Stable sort by time.
  final indexed = [for (var i = 0; i < shifted.length; i++) (i, shifted[i])];
  indexed.sort((a, b) {
    final c = a.$2.time!.compareTo(b.$2.time!);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

Duration _atLeastZero(Duration d) => d.isNegative ? Duration.zero : d;

Duration _lrcDuration(Match m) {
  final minutes = int.parse(m.group(1)!);
  final seconds = int.parse(m.group(2)!);
  final frac = m.group(3);
  var ms = 0;
  if (frac != null) {
    // ".5" = 500 ms, ".45" = 450 ms, ".456" = 456 ms
    ms = int.parse(frac.padRight(3, '0').substring(0, 3));
  }
  return Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
}

/// `mm:ss.xx`, as used in LRC files.
String formatLrcTime(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
  return '$m:$s.$cs';
}

/// Index of the last line starting at or before [position] (-1 if none).
int lyricLineAt(List<LyricLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final t = lines[mid].time;
    if (t == null) return -1;
    if (t <= position) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}

/// Timed lines back to LRC text.
String toLrc(List<LyricLine> lines) => lines.map((l) => l.toString()).join('\n');
