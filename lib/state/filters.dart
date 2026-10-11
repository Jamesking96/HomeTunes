// How a filter is described, for every tab that has a filter sheet (refactor phase 12, 9 Oct 2026):
// the Library's Artists, Albums and Songs (music_filters.dart), Audiobooks (book_index.dart's
// bookFields) and Videos (video_filters.dart's videoFilterFields). Each tab lists its FilterFields
// (a label and the values an item has); Filters holds what was picked, one value per field, and
// works out each field's choices with counts, narrowed by the other picks. The sheet that shows
// them is ui/widgets/filter_sheet.dart. Before, the Books tab had its own BookFilters as well (no
// longer used) and the class was called MusicFilters. Also the title search all the tabs share.
import 'library_index.dart' show sortKey;

// ---------------------------------------------------------------- title search

/// Splits what was typed into lower-case words.
List<String> filterWords(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// True when every word of [query] appears in [title] (ignoring case). A blank query matches all.
bool titleMatches(String title, String query) {
  final words = filterWords(query);
  if (words.isEmpty) return true;
  final t = title.toLowerCase();
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
  const FilterField(this.label, this.values, {this.order});
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
