import '../models/track.dart';

/// Pure helpers for grouping and searching tracks (no Flutter, easy to test).

int compareTracksInAlbum(Track a, Track b) {
  final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
  if (d != 0) return d;
  final t = (a.trackNumber ?? 9999).compareTo(b.trackNumber ?? 9999);
  if (t != 0) return t;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

/// Sort key that ignores a leading "The " and case.
String sortKey(String s) {
  final l = s.toLowerCase().trim();
  return l.startsWith('the ') ? l.substring(4) : l;
}

/// Groups tracks into albums, sorted by artist then album title.
List<Album> groupAlbums(Iterable<Track> tracks) {
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    (map[t.albumKey] ??= []).add(t);
  }
  final albums = [
    for (final e in map.entries)
      Album(
        key: e.key,
        title: e.value.first.album,
        artist: e.value.first.albumArtist,
        year: e.value.map((t) => t.year).whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a),
        tracks: e.value..sort(compareTracksInAlbum),
      ),
  ];
  albums.sort((a, b) {
    final c = sortKey(a.artist).compareTo(sortKey(b.artist));
    return c != 0 ? c : sortKey(a.title).compareTo(sortKey(b.title));
  });
  return albums;
}

/// Groups albums by album artist, sorted by name; each artist's albums newest first.
List<Artist> groupArtists(List<Album> albums) {
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
  static const empty = SearchResults([], [], []);
  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}

/// Every word in [query] must appear somewhere in the item's text.
/// Items whose text starts with the query rank first.
SearchResults search(String query, List<Track> tracks, List<Album> albums, List<Artist> artists,
    {int limit = 50}) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return SearchResults.empty;
  final q = words.join(' ');

  bool matches(String text) {
    final l = text.toLowerCase();
    return words.every(l.contains);
  }

  List<T> ranked<T>(Iterable<T> items, String Function(T) text, String Function(T) primary) {
    final hits = items.where((i) => matches(text(i))).toList();
    hits.sort((a, b) {
      final pa = primary(a).toLowerCase().startsWith(q) ? 0 : 1;
      final pb = primary(b).toLowerCase().startsWith(q) ? 0 : 1;
      return pa.compareTo(pb);
    });
    return hits.take(limit).toList();
  }

  return SearchResults(
    ranked<Track>(tracks, (t) => '${t.title} ${t.artist} ${t.album}', (t) => t.title),
    ranked<Album>(albums, (a) => '${a.title} ${a.artist}', (a) => a.title),
    ranked<Artist>(artists, (a) => a.name, (a) => a.name),
  );
}
