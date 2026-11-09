// Film collections, step 5 (9 Nov 2026; plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md):
// collections HomeTunes can suggest. Nothing is made until the user says yes.
//
// Three places they come from:
//  - the Jellyfin server's own collections (box sets: "James Bond Collection"),
//  - the films' .nfo files (`<set>`: Kodi, Plex and Jellyfin's way of naming a film series),
//  - similar names ("Pokémon: The First Movie", "Pokémon 2000"; "Monty Python and the Holy
//    Grail", "Monty Python's Life of Brian").
// Only films not already in a collection are suggested; a suggestion named like one of the
// user's collections offers to add the films to it.
import '../models/video_group.dart';
import '../models/video_item.dart';
import 'video_groups.dart';

/// One of the server's own collections, with HomeTunes' ids for its films. [link]: which server
/// and its collection id there, so saying yes shares it as that one (9 Nov 2026).
typedef ServerFilmSet = ({String name, String server, List<String> ids, ({String server, String id})? link});

enum SuggestionSource {
  server('From the server\'s own collections'),
  nfo('From the films\' .nfo files'),
  names('Films with similar names');

  const SuggestionSource(this.label);
  final String label;
}

class GroupSuggestion {
  GroupSuggestion({required this.name, required this.source, required this.films, this.into, this.server, this.link});

  /// For the server's own collections: which server and its id there (it's shared as that one).
  final ({String server, String id})? link;

  /// The name it would have ("Pokémon").
  final String name;
  final SuggestionSource source;

  /// The films it would hold (ones not already in a collection).
  final List<VideoCollection> films;

  /// One of the user's collections with the same name: the films would go into it.
  final VideoGroup? into;

  /// For [SuggestionSource.server]: which server ("Den").
  final String? server;

  /// What says where it came from ("From the server's own collections (Den)").
  String get why => server == null ? source.label : '${source.label} ($server)';

  /// Remembers a "No thanks": the name, any case.
  String get dismissKey => name.trim().toLowerCase();
}

/// The suggestions for [collections], best first: the server's, then .nfo sets, then similar
/// names. Each film is suggested once; ones in a group, and names in [dismissed], are left out.
List<GroupSuggestion> suggestGroups({
  required List<VideoCollection> collections,
  required VideoGroups groups,
  List<ServerFilmSet> serverSets = const [],
  Set<String> dismissed = const {},
}) {
  final free = [for (final c in collections) if (isFilm(c) && !groups.contains(c.key)) c];
  final byVideo = {for (final c in free) c.main.single.id: c};
  final used = <String>{};
  final out = <GroupSuggestion>[];
  VideoGroup? named(String name) {
    final n = name.trim().toLowerCase();
    return groups.all.where((g) => g.name.trim().toLowerCase() == n).firstOrNull;
  }

  void offer(String name, SuggestionSource source, Iterable<VideoCollection> films, {String? server, ({String server, String id})? link}) {
    final clean = name.trim();
    if (clean.isEmpty || dismissed.contains(clean.toLowerCase())) return;
    final list = [for (final c in films) if (!used.contains(c.key)) c];
    final into = named(clean);
    // Two films make a collection; one more film is worth adding to one the user has.
    if (list.length < (into == null ? 2 : 1)) return;
    // The same name twice (two servers, or a server and .nfo files): one suggestion.
    final same = out.where((s) => s.name.toLowerCase() == clean.toLowerCase()).firstOrNull;
    if (same != null) {
      same.films.addAll(list);
    } else {
      out.add(GroupSuggestion(name: clean, source: source, films: list, into: into, server: server, link: link));
    }
    used.addAll([for (final c in list) c.key]);
  }

  for (final s in serverSets) {
    offer(_withoutCollectionWord(s.name), SuggestionSource.server, [for (final id in s.ids) ?byVideo[id]],
        server: s.server, link: s.link);
  }

  final sets = <String, List<VideoCollection>>{};
  final setNames = <String, String>{};
  for (final c in free) {
    final n = c.main.single.setName?.trim();
    if (n == null || n.isEmpty) continue;
    final k = n.toLowerCase();
    (sets[k] ??= []).add(c);
    setNames[k] ??= n;
  }
  for (final e in sets.entries) {
    offer(_withoutCollectionWord(setNames[e.key]!), SuggestionSource.nfo, e.value);
  }

  // Similar names: what comes before a colon or dash with any number after it taken off
  // ("Pokémon 2000", "Pokémon: Mewtwo Returns" → Pokémon), else the first two words that
  // aren't "the" or "a" ("Monty Python's…" → Monty Python). Bigger families first.
  final families = <String, List<VideoCollection>>{};
  final labels = <String, String>{};
  for (final c in free) {
    if (used.contains(c.key)) continue;
    for (final (key, label) in _familyKeys(c.name)) {
      (families[key] ??= []).add(c);
      labels[key] ??= label;
    }
  }
  // A one-word family ("Pokémon", from "Pokémon 2000") takes in films starting with that word
  // ("Pokémon The First Movie"); a first word alone never starts one ("Love Actually").
  for (final k in [...families.keys]) {
    if (!k.startsWith('c:') || k.contains(' ')) continue;
    final word = k.substring(2);
    for (final c in free) {
      if (used.contains(c.key) || families[k]!.contains(c)) continue;
      final first = c.name.trim().split(RegExp(r'\s+')).map(_word).where((w) => w.isNotEmpty).firstOrNull;
      if (first == word) families[k]!.add(c);
    }
  }
  final keys = families.keys.toList()..sort((a, b) => families[b]!.length.compareTo(families[a]!.length));
  for (final k in keys) {
    offer(labels[k]!, SuggestionSource.names, families[k]!);
  }
  return out;
}

/// "James Bond Collection" → "James Bond" (how Jellyfin and TMDb name them).
String _withoutCollectionWord(String name) {
  final n = name.trim();
  final m = RegExp(r'^(.*?)\s*[-:]?\s*(film |movie )?collection$', caseSensitive: false).firstMatch(n);
  final rest = m?.group(1)?.trim();
  return rest == null || rest.isEmpty ? n : rest;
}

const _small = {'the', 'a', 'an', 'and', 'of', 'in', 'on', 'to', 'for', 'at', 'by', 'with', 'from', 'my', 'is'};
const _accents = {'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i',
  'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c'};

String _plain(String s) => s.toLowerCase().split('').map((ch) => _accents[ch] ?? ch).join();

/// A word as it's compared: plain letters, "Python's" → "python".
String _word(String w) => _plain(w).replaceAll(RegExp(r"['’]s$"), '').replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isNumber(String w) => RegExp(r'^(\d+|[ivx]+|part|chapter|vol|volume|episode)$').hasMatch(w);

/// The keys a film's name could share with others of its series, with the name to show for each.
List<(String, String)> _familyKeys(String name) {
  final out = <(String, String)>[];
  final cut = RegExp(r'\s*(:|\s[-–—]\s)').firstMatch(name);
  if (cut != null && cut.start > 0) {
    final words = name.substring(0, cut.start).trim().split(RegExp(r'\s+'));
    while (words.length > 1 && _isNumber(_word(words.last))) {
      words.removeLast();
    }
    final key = words.map(_word).where((w) => w.isNotEmpty).join(' ');
    if (key.isNotEmpty && !_small.contains(key)) out.add(('c:$key', _show(words)));
  }
  // Also with no colon ("Pokémon 2000"): the name without a number at the end.
  final all = name.trim().split(RegExp(r'\s+'));
  if (all.length > 1 && _isNumber(_word(all.last))) {
    final words = [...all];
    while (words.length > 1 && _isNumber(_word(words.last))) {
      words.removeLast();
    }
    final key = words.map(_word).where((w) => w.isNotEmpty).join(' ');
    if (key.isNotEmpty && !_small.contains(key)) out.add(('c:$key', _show(words)));
  }
  // The first two words that matter.
  final start = [...all];
  while (start.isNotEmpty && _small.contains(_word(start.first))) {
    start.removeAt(0);
  }
  if (start.length >= 3) {
    final two = start.take(2).toList();
    final key = two.map(_word).join(' ');
    if (two.every((w) => _word(w).length > 1 && !_small.contains(_word(w)) && !_isNumber(_word(w)))) {
      out.add(('w:$key', _show(two)));
    }
  }
  return {for (final k in out) k.$1: k}.values.toList();
}

/// The words as shown: "Python's" → "Python", any dash or colon at the end taken off.
String _show(List<String> words) => words
    .map((w) => w.replaceAll(RegExp(r"['’]s$"), ''))
    .join(' ')
    .replaceAll(RegExp(r'[\s:,\-–—]+$'), '')
    .trim();
