// Shuffle for video collections (0.2.6, the user, 29 Oct: "a shuffle feature for collections …
// on a whole collection or just a single season (when in just one season it only samples from
// said season) … an option to add or remove seasons from the sample group"). Plain Dart (no
// Flutter), tested in test/video_shuffle_test.dart.
//
// A shuffle is a random order of some of a collection's videos, made when it starts: the player
// plays on through it (Up next, next / previous) instead of the collection's own order, and stops
// at its end. Each video comes up once.
//
// What goes in:
//  * one season (its heading's Shuffle): just that season's videos;
//  * the whole collection (the page's Shuffle): the seasons and parts that are "in the shuffle".
//    Normal seasons, named parts and loose episodes are in unless taken out; Specials, seasons
//    marked special and Extras are out unless put in. The choice is kept per collection
//    (VideoLibraryModel.setInShuffle, saved in videos.json), so a season added later is in by
//    default.
import 'dart:math';

import '../models/video_item.dart';

/// One heading of a collection (a season, a named part, Specials, Extras), as the shuffle sees it.
class ShuffleGroup {
  const ShuffleGroup({required this.heading, required this.label, required this.videos, required this.included});

  /// The heading on the collection's page ("Season 2"), or null for a collection without headings.
  final String? heading;

  /// What it's called (the season's title when it has one).
  final String label;
  final List<VideoItem> videos;

  /// In the whole collection's shuffle.
  final bool included;
}

/// Whether a heading is in the whole collection's shuffle when the user hasn't said: everything
/// but Extras, Specials and seasons marked special.
bool shuffledByDefault(String? heading, List<VideoItem> videos) {
  if (heading == null) return true;
  if (videos.isEmpty) return false;
  if (videos.every((v) => v.extra)) return false;
  if (videos.every((v) => v.season == 0 || v.specialTitle != null)) return false;
  return true;
}

/// A shuffled order of some of [collection]'s videos.
class VideoShuffle {
  VideoShuffle({required this.collection, required List<String> order, required this.label}) : order = List.unmodifiable(order);

  /// Shuffles [videos] (which must not be empty). [label] says what's shuffled ("Season 2",
  /// "Seasons 1, 3", "Whole collection").
  factory VideoShuffle.of(String collection, List<VideoItem> videos, {required String label, Random? random}) =>
      VideoShuffle(collection: collection, order: [for (final v in videos) v.id]..shuffle(random ?? Random()), label: label);

  final String collection;
  final List<String> order;
  final String label;

  String get first => order.first;
  int get length => order.length;
  bool contains(String id) => order.contains(id);

  /// The video after [id] in the shuffle, or null at its end (or when [id] isn't in it).
  String? after(String id) {
    final i = order.indexOf(id);
    return i < 0 || i + 1 >= order.length ? null : order[i + 1];
  }

  /// The video before [id] in the shuffle, or null at its start.
  String? before(String id) {
    final i = order.indexOf(id);
    return i <= 0 ? null : order[i - 1];
  }

  /// "3 of 24": where [id] is in the shuffle.
  String placeOf(String id) {
    final i = order.indexOf(id);
    return i < 0 ? '' : '${i + 1} of ${order.length}';
  }
}

/// What a whole-collection shuffle of [groups] (the included ones) is called: "Whole collection"
/// when everything is in, "All seasons" when just the usual ones are (no Extras or Specials), else the included ones' names ("Season 1, Season 3"), shortened
/// to "Seasons 1, 3" when they're all plain seasons.
String shuffleLabel(List<ShuffleGroup> groups) {
  final inc = [for (final g in groups) if (g.included) g];
  if (inc.length == groups.length || inc.length == 1 && inc.single.heading == null) return 'Whole collection';
  if (inc.length == 1) return inc.single.label;
  // Just what's in by default (Extras and Specials left out): all the seasons.
  final usual = [for (final g in groups) if (shuffledByDefault(g.heading, g.videos)) g.heading];
  if (usual.length == inc.length && usual.every((h) => inc.any((g) => g.heading == h))) return 'All seasons';
  final seasons = RegExp(r'^Season (\d+(?:\.\d+)?)$');
  final numbers = [for (final g in inc) seasons.firstMatch(g.heading ?? '')?.group(1)];
  if (numbers.every((n) => n != null)) return 'Seasons ${numbers.join(', ')}';
  return inc.map((g) => g.label).join(', ');
}
