// Videos (0.1.40): .nfo files, the small XML files that Kodi, Jellyfin, Emby and Plex keep beside
// videos to hold their details. This is how editing a video or a collection "also edits the
// files": the video files themselves (mostly large MKVs) are never rewritten, but when "Also
// save into .nfo files" is ticked, VideoLibraryModel.saveNfoFiles writes
//   - `<video name>.nfo` beside each video: <episodedetails> (title, showtitle, season, episode,
//     year, genre, plot) for a series, or <movie> (title, set, year, genre, plot) otherwise;
//   - `tvshow.nfo` in a series' own folder: <tvshow> (title, year, genre, plot).
// An .nfo that's already there (made by another program) keeps everything HomeTunes doesn't
// manage; only the tags above are replaced. The scanner (video_scanner.dart) reads these files
// back, so the details survive a new install and show up in the other programs too.
// Everything here is plain file work, safe to run in a background isolate.
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// What an .nfo file says. Null means it doesn't say.
class NfoInfo {
  final String? title;

  /// The series an episode belongs to (`<showtitle>`).
  final String? showTitle;

  /// The collection ("set") a film belongs to (`<set><name>…</name></set>`).
  final String? set;
  final int? season, episode, year;
  final String? genre, plot;

  /// A series' season titles (`<namedseason number="1">Offline News</namedseason>` in tvshow.nfo).
  final Map<int, String> namedSeasons;
  const NfoInfo({
    this.title,
    this.showTitle,
    this.set,
    this.season,
    this.episode,
    this.year,
    this.genre,
    this.plot,
    this.namedSeasons = const {},
  });
}

/// The .nfo field key for a season's title: written as `<namedseason number="n">`.
String namedSeasonKey(int season) => 'namedseason:$season';

/// The .nfo file that goes with a video: same name, .nfo ending.
String nfoPathFor(String videoPath) => '${p.withoutExtension(videoPath)}.nfo';

/// The series' own .nfo, in its folder.
const showNfoName = 'tvshow.nfo';

/// Reads an .nfo file; null if it can't be read or isn't XML.
NfoInfo? readNfo(String path) {
  try {
    final text = File(path).readAsStringSync();
    return text.contains('<') ? parseNfo(text) : null;
  } catch (_) {
    return null;
  }
}

/// Pulls the details HomeTunes uses out of an .nfo's XML.
NfoInfo parseNfo(String xml) {
  String? tag(String name, [String? within]) {
    final m = RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name\\s*>', caseSensitive: false).firstMatch(within ?? xml);
    if (m == null) return null;
    final v = _unescape(m[1]!).trim();
    return v.isEmpty ? null : v;
  }

  int? number(String? s) => s == null ? null : int.tryParse(s.trim());
  // <set> is either <set><name>X</name></set> (newer Kodi) or plain <set>X</set>.
  final setRaw = RegExp(r'<set(?:\s[^>]*)?>([\s\S]*?)</set\s*>', caseSensitive: false).firstMatch(xml)?[1];
  final set = setRaw == null ? null : (setRaw.contains('<') ? tag('name', setRaw) : _nonEmpty(_unescape(setRaw).trim()));
  var year = number(tag('year'));
  if (year == null) {
    final date = tag('premiered') ?? tag('aired');
    year = date == null ? null : number(RegExp(r'\b(1[89]|20|21)\d\d\b').firstMatch(date)?[0]);
  }
  return NfoInfo(
    title: tag('title'),
    showTitle: tag('showtitle'),
    set: set,
    season: number(tag('season')),
    episode: number(tag('episode')),
    year: (year != null && year > 1800) ? year : null,
    genre: tag('genre'),
    plot: tag('plot') ?? tag('outline'),
    namedSeasons: {
      for (final m in RegExp(r'''<namedseason\s[^>]*number\s*=\s*["']?(\d+)["']?[^>]*>([\s\S]*?)</namedseason\s*>''',
              caseSensitive: false)
          .allMatches(xml))
        if (_unescape(m[2]!).trim().isNotEmpty) int.parse(m[1]!): _unescape(m[2]!).trim(),
    },
  );
}

String? _nonEmpty(String s) => s.isEmpty ? null : s;

String _unescape(String s) {
  final cdata = RegExp(r'^\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*$').firstMatch(s);
  if (cdata != null) return cdata[1]!;
  return s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16);
        return code == null ? m[0]! : String.fromCharCode(code);
      })
      .replaceAll('&amp;', '&');
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// One .nfo file to write: its path, its top element ("episodedetails", "movie", "tvshow"), and
/// the tags to set, in order. A null value removes that tag.
class NfoJob {
  final String path;
  final String root;
  final Map<String, String?> fields;
  const NfoJob(this.path, this.root, this.fields);
}

/// The new text of an .nfo: [existing] (null for a new file) with the tags in [fields] replaced,
/// and everything else in it kept.
String updateNfo(String? existing, String root, Map<String, String?> fields) {
  var text = existing;
  final open = text == null ? null : RegExp(r'<([A-Za-z_][\w.-]*)(\s[^>]*)?>').allMatches(text).where((m) {
    final name = m[1]!;
    return name != 'xml' && !m[0]!.startsWith('<?') && !m[0]!.startsWith('<!');
  }).firstOrNull;
  if (text == null || open == null || !text.contains('</${open[1]}')) {
    // New (or not a usable .nfo): start afresh.
    text = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<$root>\n</$root>\n';
  } else if (open[1]!.toLowerCase() != root) {
    // A film that became an episode (or the other way): rename the top element, keep the rest.
    final old = open[1]!;
    text = text.replaceFirst(open[0]!, '<$root${open[2] ?? ''}>');
    final close = text.lastIndexOf('</$old');
    if (close >= 0) text = text.replaceRange(close, text.indexOf('>', close) + 1, '</$root>');
  }
  final rootName = RegExp('<($root)(\\s[^>]*)?>', caseSensitive: false).firstMatch(text)![1]!;
  for (final e in fields.entries) {
    // "namedseason:2" is <namedseason number="2">: one of several, told apart by its number.
    final named = RegExp(r'^namedseason:(\d+)$').firstMatch(e.key);
    final tag = named == null ? e.key : 'namedseason';
    final attrs = named == null ? '(?:\\s[^>]*)?' : '\\s[^>]*number\\s*=\\s*["\']?${named[1]}["\']?(?![0-9])[^>]*';
    final element = RegExp('[ \\t]*<$tag$attrs(?:/>|>[\\s\\S]*?</$tag\\s*>)[ \\t]*\\r?\\n?', caseSensitive: false);
    final first = element.firstMatch(text!);
    final value = e.value?.trim();
    final line = (value == null || value.isEmpty)
        ? ''
        : tag == 'set'
            ? '  <set>\n    <name>${_escape(value)}</name>\n  </set>\n'
            : named != null
                ? '  <namedseason number="${named[1]}">${_escape(value)}</namedseason>\n'
                : '  <$tag>${_escape(value)}</$tag>\n';
    if (first != null) {
      text = text.replaceRange(first.start, first.end, line);
      // Any repeats (several <genre> tags) go: HomeTunes keeps one.
      final rest = first.start + line.length;
      text = text.substring(0, rest) + text.substring(rest).replaceAll(element, '');
    } else if (line.isNotEmpty) {
      final close = text.lastIndexOf('</$rootName');
      final lineStart = text.lastIndexOf('\n', close - 1) + 1;
      final at = text.substring(lineStart, close).trim().isEmpty ? lineStart : close;
      text = text.replaceRange(at, at, at == close ? '\n$line' : line);
    }
  }
  return text!;
}

/// Writes each job; returns "file: reason" for the ones that failed. A file is written beside
/// itself first and then swapped in, so a failed write never leaves half a file.
List<String> writeNfoFiles(List<NfoJob> jobs) {
  final errors = <String>[];
  for (final job in jobs) {
    final file = File(job.path);
    final work = File('${job.path}.hometunes-tmp');
    try {
      final existing = file.existsSync() ? file.readAsStringSync() : null;
      final text = updateNfo(existing, job.root, job.fields);
      if (text == existing) continue;
      work.writeAsStringSync(text, flush: true);
      work.renameSync(job.path);
    } catch (e) {
      try {
        if (work.existsSync()) work.deleteSync();
      } catch (_) {}
      errors.add('${p.basename(job.path)}: ${e is FileSystemException ? (e.osError?.message ?? e.message) : e}');
    }
  }
  return errors;
}

/// [writeNfoFiles] in a background isolate.
Future<List<String>> writeNfoFilesInBackground(List<NfoJob> jobs) => Isolate.run(() => writeNfoFiles(jobs));
