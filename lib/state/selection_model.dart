// Multi-select state for song lists.
//
// When the user long-presses a song (or picks ⋮ → Select), the app goes into "select mode" and
// this model remembers which song ids are ticked. Song lists and the selection bar at the top
// of the screen watch it, so they can show tick boxes and actions like "Edit" or "Add to
// playlist" that apply to every ticked song at once. Select mode is simply "one or more ticked".
import 'package:flutter/foundation.dart';

/// Songs ticked in "select" mode (long-press a song, or ⋮ → Select), so they
/// can be edited or added to a playlist together.
class SelectionModel extends ChangeNotifier {
  /// The ticked song ids (Track ids such as `local:<path>` or `server:<id>`).
  final Set<String> _ids = {};

  /// A read-only copy, so callers can't change the selection behind our back.
  Set<String> get ids => Set.unmodifiable(_ids);
  /// True while at least one song is ticked, i.e. select mode is on.
  bool get active => _ids.isNotEmpty;
  int get count => _ids.length;
  bool contains(String id) => _ids.contains(id);

  /// Ticks the song if it wasn't ticked, or unticks it if it was.
  void toggle(String id) {
    // `remove` returns false when the id wasn't there, which means we should add it instead.
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  /// Ticks every song in [ids] (used by "Select all"), keeping any already ticked.
  void selectAll(Iterable<String> ids) {
    _ids.addAll(ids);
    notifyListeners();
  }

  /// Unticks everything, which also leaves select mode.
  void clear() {
    // Skip the redraw if there was nothing to clear.
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}
