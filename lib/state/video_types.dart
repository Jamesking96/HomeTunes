// What type of thing a video or collection is: Anime, TV, Films, or another kind the user's
// libraries name (0.2.5, the user, 29 Oct: "a new category at the top of the TV's Video tab that
// splits the shows up based on the type they are … to see things like Anime, TV or Films without
// looking through the whole list"). Plain functions (no Flutter), tested in test/video_types_test.dart.
//
// The type is the video's category: the category folder its file is in ("TV", "Anime", "Film"),
// or for a Jellyfin video the library it's in (server_videos.dart: the user's server has "Anime",
// "Shows" and "Movies" libraries). Names that mean the same thing count as one: "Film", "Films",
// "Movie(s)" are Films; "TV", "Shows", "TV Shows", "Series" are TV; anything with "anime" in it is
// Anime. Genres don't decide it: "Animation" covers anime and cartoons such as South Park alike.
//
// The TV's Videos tab also filters by watched state, genre and where things come from, and sorts
// by Most episodes and Not watched first, all here.
import '../models/video_item.dart';
import 'library_index.dart' show sortKey;
import 'source_filter.dart';

/// The type a category (folder or library name) stands for, or null when there's none.
String? videoType(String? category) {
  final c = (category ?? '').trim();
  if (c.isEmpty) return null;
  final l = c.toLowerCase();
  if (l.contains('anime')) return 'Anime';
  if (const {'film', 'films', 'movie', 'movies'}.contains(l)) return 'Films';
  if (const {'tv', 'shows', 'show', 'tv shows', 'tv show', 'series', 'tv series', 'television'}.contains(l)) return 'TV';
  return c;
}

/// A collection's type: the one most of its videos have (its own category when they have none).
String? collectionType(VideoCollection c) {
  final counts = <String, int>{};
  for (final v in c.videos) {
    final t = videoType(v.category);
    if (t != null) counts[t] = (counts[t] ?? 0) + 1;
  }
  if (counts.isEmpty) return videoType(c.category);
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// The types there are among [types], in the order the buttons show them: Anime, TV, Films, then
/// any others A–Z.
List<String> orderTypes(Iterable<String?> types) {
  const first = ['Anime', 'TV', 'Films'];
  final present = {for (final t in types) ?t};
  return [
    for (final t in first) if (present.contains(t)) t,
    ...(present.where((t) => !first.contains(t)).toList()..sort((a, b) => sortKey(a).compareTo(sortKey(b)))),
  ];
}

/// The watched states the Filter offers.
enum WatchState {
  notStarted('Not started'),
  inProgress('In progress'),
  watched('Watched');

  const WatchState(this.label);
  final String label;
}

/// Where things come from, as the Filter offers it.
enum SourceChoice {
  onThisDevice('On this device'),
  streamed('Streamed'),
  downloaded('Downloaded');

  const SourceChoice(this.label);
  final String label;

  bool matches(MediaSource s) => switch (this) {
        onThisDevice => s == MediaSource.local,
        streamed => s == MediaSource.streamed,
        downloaded => s == MediaSource.downloaded || s == MediaSource.temporary,
      };
}

/// What the TV's Videos tab is showing: a type (null: all), and the Filter's choices (null: any).
class VideoChoice {
  const VideoChoice({this.type, this.watch, this.genre, this.source});
  final String? type;
  final WatchState? watch;
  final String? genre;
  final SourceChoice? source;

  /// How many of the Filter's choices are set (the type has its own buttons).
  int get filters => (watch == null ? 0 : 1) + (genre == null ? 0 : 1) + (source == null ? 0 : 1);

  VideoChoice copyWith({String? type, WatchState? watch, String? genre, SourceChoice? source, Set<String> clear = const {}}) =>
      VideoChoice(
        type: clear.contains('type') ? null : (type ?? this.type),
        watch: clear.contains('watch') ? null : (watch ?? this.watch),
        genre: clear.contains('genre') ? null : (genre ?? this.genre),
        source: clear.contains('source') ? null : (source ?? this.source),
      );

  /// The Filter's choices taken away; the type stays.
  VideoChoice get withoutFilters => VideoChoice(type: type);
}

/// A collection's watched state: [watchedCount] of its [main] videos watched, [started] whether
/// any is part-way through.
WatchState collectionWatchState({required int watchedCount, required int main, required bool started}) {
  if (main > 0 && watchedCount >= main) return WatchState.watched;
  if (watchedCount > 0 || started) return WatchState.inProgress;
  return WatchState.notStarted;
}

/// A video's watched state from its [place].
WatchState videoWatchState(VideoPlace? place) {
  if (place != null && place.watched) return WatchState.watched;
  if (place != null && place.inProgress) return WatchState.inProgress;
  return WatchState.notStarted;
}

/// A collection's genre: the one most of its videos have.
String? collectionGenre(VideoCollection c) {
  final counts = <String, int>{};
  for (final v in c.videos) {
    final g = v.genre?.trim();
    if (g != null && g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
  }
  if (counts.isEmpty) return (c.genre?.trim().isEmpty ?? true) ? null : c.genre!.trim();
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// The collections in [all] that [choice] lets through. [stateOf] gives a collection's watched state.
List<VideoCollection> chooseCollections(
  List<VideoCollection> all,
  VideoChoice choice, {
  required WatchState Function(VideoCollection c) stateOf,
}) =>
    [
      for (final c in all)
        if ((choice.type == null || collectionType(c) == choice.type) &&
            (choice.watch == null || stateOf(c) == choice.watch) &&
            (choice.genre == null || collectionGenre(c) == choice.genre) &&
            (choice.source == null || sourcesOfVideos(c.videos).any(choice.source!.matches)))
          c,
    ];

/// The videos in [all] that [choice] lets through. [placeOf] gives a video's place.
List<VideoItem> chooseVideos(List<VideoItem> all, VideoChoice choice, {required VideoPlace? Function(String id) placeOf}) => [
      for (final v in all)
        if ((choice.type == null || videoType(v.category) == choice.type) &&
            (choice.watch == null || videoWatchState(placeOf(v.id)) == choice.watch) &&
            (choice.genre == null || v.genre?.trim() == choice.genre) &&
            (choice.source == null || choice.source!.matches(sourceOfVideo(v))))
          v,
    ];

/// The genres among [collections] (or [videos]), A–Z.
List<String> genresOf({Iterable<VideoCollection> collections = const [], Iterable<VideoItem> videos = const []}) {
  final out = <String>{
    for (final c in collections) ?collectionGenre(c),
    for (final v in videos)
      if (v.genre != null && v.genre!.trim().isNotEmpty) v.genre!.trim(),
  };
  return out.toList()..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
}

/// Most episodes first (main videos, then all), A–Z among equals.
List<VideoCollection> byMostEpisodes(List<VideoCollection> list) => [...list]..sort((a, b) {
    final c = b.main.length.compareTo(a.main.length);
    if (c != 0) return c;
    final d = b.videos.length.compareTo(a.videos.length);
    return d != 0 ? d : sortKey(a.name).compareTo(sortKey(b.name));
  });

/// Not started first, then in progress, then watched; A–Z within each.
List<T> byNotWatchedFirst<T>(List<T> list, WatchState Function(T x) stateOf, String Function(T x) name) => [...list]
  ..sort((a, b) {
    final c = stateOf(a).index.compareTo(stateOf(b).index);
    return c != 0 ? c : sortKey(name(a)).compareTo(sortKey(name(b)));
  });
