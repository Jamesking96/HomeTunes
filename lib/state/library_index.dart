// Grouping and search helpers for the music side of the library.
//
// These are plain functions with no Flutter in them, so they're quick and easy to unit test.
// LibraryModel calls them every time it rebuilds the library: `groupAlbums` turns the flat list
// of songs into albums, `groupArtists` turns albums into artists, and `search` powers the
// search box. Albums are keyed by album artist + album name (see `Track.albumKey`), and
// sorting ignores a leading "The " so "The Beatles" sits under B.
import '../models/track.dart';

/// Pure helpers for grouping and searching tracks (no Flutter, easy to test).

/// Orders songs inside an album: by disc, then track number, then title.
/// Songs with no disc number count as disc 1; songs with no track number go to the end.
int compareTracksInAlbum(Track a, Track b) {
  final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (d != 0) return d;
  final t = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
  if (t != 0) return t;
  // Same disc and track number (or neither has one): fall back to the title, ignoring case.
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Sort key that ignores a leading "The " and case.
String sortKey(String s) {
  final l = s.toLowerCase().trim();
  return l.startsWith('the ') ? l.substring(4) : l;
}

/// Groups tracks into albums, sorted by artist then album title.
List<Album> groupAlbums(Iterable<Track> tracks) {
  // 1. Bucket the songs by their album key (album artist + album name).
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    (map[t.albumKey] ??= []).add(t);
  }
  // 2. Build one Album per bucket. The title and artist come from the first song. The key
  //    ignores case, so "Abbey Road" and "abbey road" share a bucket; the first spelling wins.
  final albums = [
    for (final e in map.entries)
      Album(
        key: e.key,
        title: e.value.first.album,
        artist: e.value.first.albumArtist,
        // The album's year is the earliest year found on any of its songs (null if none).
        year: e.value.map((t) => t.year).whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a),
        tracks: e.value..sort(compareTracksInAlbum), // sorts the list in place, then passes it on
      ),
  ];
  // 3. Sort the albums by artist, then by title, both ignoring "The " and case.
  albums.sort((a, b) {
    final c = sortKey(a.artist).compareTo(sortKey(b.artist));
    return c != 0 ? c : sortKey(a.title).compareTo(sortKey(b.title));
  });
  return albums;
}

/// Groups albums by album artist, sorted by name; each artist's albums newest first.
List<Artist> groupArtists(List<Album> albums) {
  // Artists are matched ignoring case, so "ABBA" and "Abba" become one artist. `names` keeps
  // the spelling from the first album seen, to use as the display name.
  final map = <String, List<Album>>{};
  final names = <String, String>{};
  for (final a in albums) {
    final k = a.artist.toLowerCase();
    (map[k] ??= []).add(a);
    names[k] ??= a.artist;
  }
  final artists = [
    for (final e in map.entries)
      Artist(
        name: names[e.key]!,
        // Newest album first; albums with no year sort as year 0, so they end up last.
        albums: e.value..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0)),
      ),
  ];
  artists.sort((a, b) => sortKey(a.name).compareTo(sortKey(b.name)));
  return artists;
}

/// Search results across the library.
class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  const SearchResults(this.tracks, this.albums, this.artists);
  /// A shared "nothing found" result, used for a blank query.
  static const empty = SearchResults([], [], []);
  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Every word in [query] must appear somewhere in the item's text.
/// Items whose text starts with the query rank first.
SearchResults search(String query, List<Track> tracks, List<Album> albums, List<Artist> artists,
    {int limit = 50}) {
  // Split the query into lower-case words, dropping extra spaces. Nothing typed = no results.
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return SearchResults.empty;
  // The tidied-up query, used to spot items whose name starts with exactly what was typed.
  final q = words.join(' ');

  // An item matches if every typed word appears somewhere in its text, in any order.
  bool matches(String text) {
    final l = text.toLowerCase();
    return words.every(l.contains);
  }

  // Filters [items], moves those whose main name starts with the query to the top, and keeps
  // at most [limit]. Note Dart's sort isn't guaranteed to keep the original order of "equal"
  // items, so within each of the two groups the order may get shuffled a little.
  List<T> ranked<T>(Iterable<T> items, String Function(T) text, String Function(T) primary) {
    final hits = items.where((i) => matches(text(i))).toList();
    hits.sort((a, b) {
      final pa = primary(a).toLowerCase().startsWith(q) ? 0 : 1;
      final pb = primary(b).toLowerCase().startsWith(q) ? 0 : 1;
      return pa.compareTo(pb);
    });
    return hits.take(limit).toList();
  }

  // Songs match on title/artist/album, albums on title/artist, artists on their name.
  return SearchResults(
    ranked<Track>(tracks, (t) => '${t.title} ${t.artist} ${t.album}', (t) => t.title),
    ranked<Album>(albums, (a) => '${a.title} ${a.artist}', (a) => a.title),
    ranked<Artist>(artists, (a) => a.name, (a) => a.name),
  );
}
