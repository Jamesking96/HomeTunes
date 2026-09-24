import 'package:flutter/foundation.dart';

/// Songs ticked in "select" mode (long-press a song, or ⋮ → Select), so they
/// can be edited or added to a playlist together.
class SelectionModel extends ChangeNotifier {
  final Set<String> _ids = {};

  Set<String> get ids => Set.unmodifiable(_ids);
  bool get active => _ids.isNotEmpty;
  int get count => _ids.length;
  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _ids.addAll(ids);
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }
}
