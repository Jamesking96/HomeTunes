// Shift + click to select a range (0.1.47, the user's request: "When using the select feature, I
// want to add holding shift to select everything between two points").
//
// While selecting, the last thing clicked is remembered (the "anchor"). Clicking another one with
// Shift held ticks everything from the anchor to it, in the order they're shown, as file managers
// do; the ones already ticked stay ticked. Shift + click with nothing selected yet starts selecting
// with that one. Used by SelectionModel (songs, albums, audiobooks) and by the Videos tab's own
// selections (videos, collections, a collection's episodes) through [RangePicker].
import 'package:flutter/services.dart';

/// Whether Shift is held down right now (on a keyboard; never on a phone without one).
bool get shiftHeld => HardwareKeyboard.instance.isShiftPressed;

/// The ids from [from] to [to] in [order], both included, whichever way round they are. Null when
/// either isn't in [order].
List<String>? idsBetween(List<String> order, String from, String to) {
  final a = order.indexOf(from), b = order.indexOf(to);
  if (a < 0 || b < 0) return null;
  return a <= b ? order.sublist(a, b + 1) : order.sublist(b, a + 1);
}

/// Ticking things in a set, with Shift + click for a range.
class RangePicker {
  /// The last one clicked.
  String? anchor;

  /// [id] was clicked while selecting: with Shift held and an anchor in [order], ticks everything
  /// between them; otherwise ticks or unticks [id]. Either way [id] becomes the anchor. With
  /// nothing ticked (a new selection), an old anchor is ignored.
  void pick(Set<String> selected, String id, List<String> order) {
    final range = shiftHeld && anchor != null && selected.isNotEmpty ? idsBetween(order, anchor!, id) : null;
    if (range != null) {
      selected.addAll(range);
    } else if (!selected.remove(id)) {
      selected.add(id);
    }
    anchor = id;
  }

  void clear() => anchor = null;
}
