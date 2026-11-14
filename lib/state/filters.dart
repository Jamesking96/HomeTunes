// How a filter is described, for every tab that has a filter sheet (refactor phase 12, 9 Oct 2026):
// the Library's Artists, Albums and Songs (music_filters.dart), Audiobooks (book_index.dart's
// bookFields) and Videos (video_filters.dart's videoFilterFields). Each tab lists its FilterFields
// (a label and the values an item has); Filters holds what was picked, one value per field, and
// works out each field's choices with counts, narrowed by the other picks. The sheet that shows
// them is ui/widgets/filter_sheet.dart. Before, the Books tab had its own BookFilters as well (no
// longer used) and the class was called MusicFilters. Also the title search all the tabs share.
import 'library_index.dart' show sortKey;

// ---------------------------------------------------------------- title search

/// Text as searches compare it (14 Nov 2026): lower case, with accents taken off, so "pokemon"
/// finds "Pokémon" and "Pokémon" finds "Pokemon".
String searchText(String s) {
  final lower = s.toLowerCase();
  if (!_hasAccent.hasMatch(lower)) return lower;
  final b = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    b.write(_plain[ch] ?? ch);
  }
  return b.toString();
}

final _hasAccent = RegExp(r'[^\x00-\x7f]');
const _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'æ': 'ae',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'ð': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i', 'ı': 'i',
  'ł': 'l', 'ľ': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'œ': 'oe',
  'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
  'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
  '’': "'", '‘': "'", '“': '"', '”': '"', '–': '-', '—': '-',
};

/// Splits what was typed into words, as searches compare them ([searchText]).
List<String> filterWords(String query) =>
    searchText(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// True when every word of [query] appears in [title] (ignoring case and accents). A blank query
/// matches all.
bool titleMatches(String title, String query) {
  final words = filterWords(query);
  if (words.isEmpty) return true;
  final t = searchText(title);
  return words.every(t.contains);
}

// ---------------------------------------------------------------- filters

/// "1990s" for 1994; null when there's no (sensible) year.
String? decadeOf(int? year) => year == null || year <= 0 ? null : '${year ~/ 10 * 10}s';

/// One thing the filter sheet can narrow by, e.g. "Genre". [values] gives the choices an item
/// has (an album can have songs in several genres, so it's a list).
class FilterField<T> {
  final String label;
  final Iterable<String> Function(T item) values;

  /// The order the choices are listed in, when A–Z doesn't fit (e.g. lengths shortest first;
  /// the Videos tab, 0.1.40). Null: A–Z.
  final int Function(String a, String b)? order;

  /// Only shown in the sheet when the items have two or more choices, or one is picked (the
  /// Source field, 0.2.2: no point offering it when everything is on this device).
  final bool onlyWhenSeveral;
  const FilterField(this.label, this.values, {this.order, this.onlyWhenSeveral = false});
}

/// The choices picked in a filter sheet, by field label (e.g. {"Genre": "Jazz"}).
class Filters {
  final Map<String, String> picked;
  const Filters([this.picked = const {}]);

  /// Nothing picked: everything shows.
  static const none = Filters();

  bool get isEmpty => picked.isEmpty;

  /// True when [item] has every picked value. [skip] leaves one field out (used so each
  /// dropdown's choices are narrowed by the other picks but not by itself).
  bool matches<T>(T item, List<FilterField<T>> fields, {String? skip}) {
    for (final f in fields) {
      if (f.label == skip) continue;
      final want = picked[f.label];
      if (want != null && !f.values(item).contains(want)) return false;
    }
    return true;
  }

  /// A copy with [label] set to [value], or removed when [value] is null.
  Filters withValue(String label, String? value) {
    final next = {...picked};
    value == null ? next.remove(label) : next[label] = value;
    return Filters(next);
  }

  /// The choices for [field] among [items] (narrowed by the other picks), with how many
  /// items have each, sorted A–Z (decades oldest first).
  Map<String, int> choices<T>(Iterable<T> items, List<FilterField<T>> fields, FilterField<T> field) {
    final counts = <String, int>{};
    for (final i in items) {
      if (!matches(i, fields, skip: field.label)) continue;
      for (final v in field.values(i).toSet()) {
        if (v.isNotEmpty) counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    final keys = counts.keys.toList()..sort(field.order ?? (a, b) => sortKey(a).compareTo(sortKey(b)));
    return {for (final k in keys) k: counts[k]!};
  }
}
