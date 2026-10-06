// Ascending / descending for every sort (0.1.69, the user's request: "when sorting, add an
// ascending / descending option for each").
//
// Every sort menu (Your Library's Artists, Albums and Songs, Audiobooks, Videos' collections and
// videos) has Ascending and Descending under its sorts. What they mean depends on the sort, and
// the menu says so: names go A to Z, dates oldest first, counts fewest first, lengths shortest
// first. Each sort starts in its usual direction (names A to Z; dates, counts and lengths from
// the top: newest, most, longest), and picking another sort goes back to that sort's usual
// direction. The direction isn't saved, like the sort itself.

/// What a sort orders by, which decides the words for its two directions and which one it starts
/// in.
enum SortWords {
  /// Names and titles: A to Z first.
  text,

  /// Seasons, episodes, the order things come in: first to last first.
  order,

  /// Dates and "recently …": newest first.
  date,

  /// Counts (most albums, most songs, most videos): most first.
  number,

  /// Lengths: longest first.
  length;

  /// The words for ascending / descending ("A to Z" / "Z to A").
  (String, String) get words => switch (this) {
        text => ('A to Z', 'Z to A'),
        order => ('First to last', 'Last to first'),
        date => ('Oldest first', 'Newest first'),
        number => ('Fewest first', 'Most first'),
        length => ('Shortest first', 'Longest first'),
      };

  /// Whether the sort starts descending (newest, most, longest at the top).
  bool get startsDescending => this == date || this == number || this == length;
}

/// The list the other way round.
List<T> reversedIf<T>(bool reverse, List<T> items) => reverse ? items.reversed.toList() : items;

/// Headed groups the other way round: the groups in the opposite order, and what's in each.
List<(String?, List<T>)> reverseGroupsIf<T>(bool reverse, List<(String?, List<T>)> groups) =>
    reverse ? [for (final (h, l) in groups.reversed) (h, l.reversed.toList())] : groups;
