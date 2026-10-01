// Sorting, filtering and title search for the Artists, Albums and Songs tabs in Your Library.
//
// HomeTunes (0.1.18): these tabs work like the Books tab. Each has a box to filter by title
// (every typed word must appear in the title, in any order), a filter sheet to show only one
// artist / album / genre / decade, and a sort menu. Like book_index.dart, this file has no
// Flutter in it so it's easy to unit test; the tabs live in ui/screens/library_screen.dart.
import '../models/track.dart';
import 'library_index.dart';

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
class MusicFilters {
  final Map<String, String> picked;
  const MusicFilters([this.picked = const {}]);

  /// Nothing picked: everything shows.
  static const none = MusicFilters();

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
  MusicFilters withValue(String label, String? value) {
    final next = {...picked};
    value == null ? next.remove(label) : next[label] = value;
    return MusicFilters(next);
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

/// Genres of a song (none when it has no genre).
Iterable<String> _genres(Track t) => [if (t.genre != null && t.genre!.trim().isNotEmpty) t.genre!.trim()];

/// What the Artists tab can filter by.
final List<FilterField<Artist>> artistFields = [
  FilterField('Genre', (a) => a.tracks.expand(_genres)),
  FilterField('Decade', (a) => a.albums.map((al) => decadeOf(al.year)).whereType<String>()),
];

/// What the Albums tab can filter by.
final List<FilterField<Album>> albumFields = [
  FilterField('Artist', (a) => [a.artist]),
  FilterField('Genre', (a) => a.tracks.expand(_genres)),
  FilterField('Decade', (a) => [?decadeOf(a.year)]),
];

/// What the Songs tab can filter by.
final List<FilterField<Track>> songFields = [
  FilterField('Artist', (t) => {t.artist, t.albumArtist}.where((s) => s.isNotEmpty)),
  FilterField('Album', (t) => [if (t.album.isNotEmpty) t.album]),
  FilterField('Genre', _genres),
  FilterField('Decade', (t) => [?decadeOf(t.year)]),
];

// ---------------------------------------------------------------- sorting

/// "Recently added" means the most recently changed file (as for albums and books).
int _added(Iterable<Track> tracks) => tracks.fold<int>(0, (m, t) => (t.modifiedMs ?? 0) > m ? (t.modifiedMs ?? 0) : m);

int _byName(String a, String b) => sortKey(a).compareTo(sortKey(b));

/// Sort choices on the Artists tab.
enum ArtistSort { name, nameDescending, mostAlbums, mostSongs, recentlyAdded }

List<Artist> sortArtists(Iterable<Artist> artists, ArtistSort sort) {
  final list = [...artists];
  int name(Artist a, Artist b) => _byName(a.name, b.name);
  switch (sort) {
    case ArtistSort.name:
      list.sort(name);
    case ArtistSort.nameDescending:
      list.sort((a, b) => name(b, a));
    case ArtistSort.mostAlbums:
      list.sort((a, b) {
        final c = b.albums.length.compareTo(a.albums.length);
        return c != 0 ? c : name(a, b);
      });
    case ArtistSort.mostSongs:
      list.sort((a, b) {
        final c = b.tracks.length.compareTo(a.tracks.length);
        return c != 0 ? c : name(a, b);
      });
    case ArtistSort.recentlyAdded:
      list.sort((a, b) {
        final c = _added(b.tracks).compareTo(_added(a.tracks));
        return c != 0 ? c : name(a, b);
      });
  }
  return list;
}

/// Sort choices on the Albums tab.
enum AlbumSort { artist, title, newest, oldest, recentlyAdded }

/// Heading for albums with no year (listed last in the year sorts).
const noYear = 'Year not known';

/// Albums in display order. The year sorts split them into one headed group per decade;
/// the others give a single group with no heading.
List<(String?, List<Album>)> sortAlbums(Iterable<Album> albums, AlbumSort sort) {
  final list = [...albums];
  int title(Album a, Album b) => _byName(a.title, b.title);
  int artist(Album a, Album b) {
    final c = _byName(a.artist, b.artist);
    return c != 0 ? c : title(a, b);
  }

  switch (sort) {
    case AlbumSort.artist:
      return [(null, list..sort(artist))];
    case AlbumSort.title:
      return [(null, list..sort((a, b) {
        final c = title(a, b);
        return c != 0 ? c : artist(a, b);
      }))];
    case AlbumSort.recentlyAdded:
      return [(null, list..sort((a, b) {
        final c = _added(b.tracks).compareTo(_added(a.tracks));
        return c != 0 ? c : artist(a, b);
      }))];
    case AlbumSort.newest:
    case AlbumSort.oldest:
      final newest = sort == AlbumSort.newest;
      list.sort((a, b) {
        // Albums with no year go last either way.
        final ya = a.year ?? 0, yb = b.year ?? 0;
        if ((ya <= 0) != (yb <= 0)) return ya <= 0 ? 1 : -1;
        final c = newest ? yb.compareTo(ya) : ya.compareTo(yb);
        return c != 0 ? c : artist(a, b);
      });
      final groups = <(String?, List<Album>)>[];
      for (final a in list) {
        final d = decadeOf(a.year) ?? noYear;
        if (groups.isEmpty || groups.last.$1 != d) groups.add((d, []));
        groups.last.$2.add(a);
      }
      return groups;
  }
}

/// Sort choices on the Songs tab.
enum SongSort { title, artist, album, newest, recentlyAdded, longest }

List<Track> sortSongs(Iterable<Track> songs, SongSort sort) {
  final list = [...songs];
  int title(Track a, Track b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
  int then(int c, Track a, Track b) => c != 0 ? c : title(a, b);
  switch (sort) {
    case SongSort.title:
      list.sort(title);
    case SongSort.artist:
      // By artist, then each album in order, so an artist's songs play naturally.
      list.sort((a, b) {
        final c = _byName(a.artist, b.artist);
        if (c != 0) return c;
        final al = _byName(a.album, b.album);
        return al != 0 ? al : compareTracksInAlbum(a, b);
      });
    case SongSort.album:
      list.sort((a, b) {
        final c = _byName(a.album, b.album);
        if (c != 0) return c;
        final ar = _byName(a.albumArtist, b.albumArtist);
        return ar != 0 ? ar : compareTracksInAlbum(a, b);
      });
    case SongSort.newest:
      list.sort((a, b) {
        final ya = a.year ?? 0, yb = b.year ?? 0;
        if ((ya <= 0) != (yb <= 0)) return ya <= 0 ? 1 : -1;
        return then(yb.compareTo(ya), a, b);
      });
    case SongSort.recentlyAdded:
      list.sort((a, b) => then((b.modifiedMs ?? 0).compareTo(a.modifiedMs ?? 0), a, b));
    case SongSort.longest:
      list.sort((a, b) => then(b.duration.compareTo(a.duration), a, b));
  }
  return list;
}
