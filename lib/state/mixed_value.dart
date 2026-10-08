// Editing several things at once (refactor phase 2, 8 Oct 2026): what each box starts with.
// Every editor for several items (songs and albums, books, videos, video collections) asks the
// same question per box: do they all have the same value, and if so which? Each editor had its
// own copy of the answer; they now share this one. No Flutter, so it's tested directly.

/// Shown as the hint in a box whose value differs between the items being edited. Leaving it
/// keeps each one's own value.
const differentMarker = '--:--';

/// The value every one of [values] shares (`differ: false`), or `differ: true` (and no value)
/// when they don't all have the same one. With no values at all, `differ` is false and the
/// value is null.
({bool differ, T? value}) sharedValue<T>(Iterable<T> values) {
  final distinct = values.toSet();
  if (distinct.length > 1) return (differ: true, value: null);
  return (differ: false, value: distinct.isEmpty ? null : distinct.single);
}
