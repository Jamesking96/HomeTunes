// Videos (0.1.32): the Videos tab's search, "show" chips and sort orders, as plain functions
// (no Flutter), so they're unit tested directly (test/videos_test.dart).
import '../models/video_item.dart';

/// The chips along the top of the Videos tab.
enum VideoShow { all, continueWatching, unwatched, watched }

/// The sort menu. Some sorts split the grid into headed groups.
enum VideoSort { collection, title, recentlyAdded, recentlyWatched, year, longest }

String videoShowLabel(VideoShow s) => switch (s) {
      VideoShow.all => 'All',
      VideoShow.continueWatching => 'Continue watching',
      VideoShow.unwatched => 'Not watched',
      VideoShow.watched => 'Watched',
    };

String videoSortLabel(VideoSort s) => switch (s) {
      VideoSort.collection => 'Collection',
      VideoSort.title => 'Title',
      VideoSort.recentlyAdded => 'Recently added',
      VideoSort.recentlyWatched => 'Recently watched',
      VideoSort.year => 'Year (newest first)',
      VideoSort.longest => 'Longest first',
    };

/// Whether a video with [place] belongs under chip [show].
bool videoShown(VideoShow show, VideoPlace? place) => switch (show) {
      VideoShow.all => true,
      VideoShow.continueWatching => place != null && place.inProgress,
      VideoShow.unwatched => place == null || !place.watched,
      VideoShow.watched => place != null && place.watched,
    };

/// Videos whose title, collection, genre or year contain every word of [query] (any order).
List<VideoItem> searchVideos(List<VideoItem> videos, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return videos;
  return [
    for (final v in videos)
      if (words.every((w) => '${v.title} ${v.collection} ${v.genre ?? ''} ${v.year ?? ''}'.toLowerCase().contains(w))) v
  ];
}

int _byTitle(VideoItem a, VideoItem b) {
  final t = a.title.toLowerCase().compareTo(b.title.toLowerCase());
  return t != 0 ? t : a.path.compareTo(b.path);
}

/// Sorts [videos] and, for the collection and year sorts, splits them into groups with a heading.
/// Other sorts give one group with no heading. Collections are A–Z and within one the videos go
/// by title, which puts numbered episodes ("01 …", "02 …") in order.
List<(String?, List<VideoItem>)> sortVideos(
  List<VideoItem> videos,
  VideoSort sort, {
  Map<String, VideoPlace> places = const {},
}) {
  final list = List.of(videos);
  switch (sort) {
    case VideoSort.collection:
      final groups = <String, List<VideoItem>>{};
      for (final v in list..sort(_byTitle)) {
        (groups[v.collection] ??= []).add(v);
      }
      final keys = groups.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return [for (final k in keys) (k, groups[k]!)];
    case VideoSort.year:
      final groups = <int?, List<VideoItem>>{};
      for (final v in list..sort(_byTitle)) {
        (groups[v.year] ??= []).add(v);
      }
      final years = groups.keys.whereType<int>().toList()..sort((a, b) => b.compareTo(a));
      return [
        for (final y in years) ('$y', groups[y]!),
        if (groups[null] != null) ('Year not known', groups[null]!),
      ];
    case VideoSort.title:
      return [(null, list..sort(_byTitle))];
    case VideoSort.recentlyAdded:
      return [
        (null, list..sort((a, b) {
          final c = (b.addedMs ?? 0).compareTo(a.addedMs ?? 0);
          return c != 0 ? c : _byTitle(a, b);
        }))
      ];
    case VideoSort.recentlyWatched:
      // Watched or started ones first, most recent first; the rest by title.
      return [
        (null, list..sort((a, b) {
          final c = (places[b.id]?.updatedMs ?? 0).compareTo(places[a.id]?.updatedMs ?? 0);
          return c != 0 ? c : _byTitle(a, b);
        }))
      ];
    case VideoSort.longest:
      return [
        (null, list..sort((a, b) {
          final c = b.duration.compareTo(a.duration);
          return c != 0 ? c : _byTitle(a, b);
        }))
      ];
  }
}

/// Where to start playing: the saved place, unless it's right at the start or the video was
/// finished (then from the beginning).
Duration resumeAt(VideoPlace? place, Duration length) {
  if (place == null || place.position < const Duration(seconds: 5)) return Duration.zero;
  if (length > Duration.zero && isNearEnd(place.position, length)) return Duration.zero;
  return place.position;
}

/// Close enough to the end to count as watched: the last 5 %, or the last 20 seconds.
bool isNearEnd(Duration position, Duration length) {
  if (length <= Duration.zero) return false;
  return position >= length * 0.95 || length - position <= const Duration(seconds: 20);
}
