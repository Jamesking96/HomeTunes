// What's ticked in select mode: songs, albums or audiobooks (one kind at a time).
//
// Songs: long-press a song, or ⋮ → Select. Albums and books: right-click a tile
// (or press and hold on a phone) → Select / Select all. The bar at the bottom of
// the screen (shell.dart) then offers what can be done with them together, such
// as Edit details, Edit albums or Edit books. Shift + click ticks everything between the last
// one clicked and this one (0.1.47, [pick]).

import 'package:flutter/foundation.dart';

import 'range_select.dart';

/// What kind of thing is being selected.
enum SelectKind { songs, albums, books }

class SelectionModel extends ChangeNotifier {
  final Set<String> _ids = {};

  /// What the ticked ids are: song ids, album keys or book ids.
  SelectKind kind = SelectKind.songs;

  // Everything shown where selecting started, for "Select all".
  List<String> _scope = const [];

  Set<String> get ids => Set.unmodifiable(_ids);
  bool get active => _ids.isNotEmpty;
  int get count => _ids.length;

  /// True while things of [k] are being selected.
  bool selecting(SelectKind k) => active && kind == k;

  /// Whether [id] (of [kind]) is ticked.
  bool contains(String id, {SelectKind kind = SelectKind.songs}) => this.kind == kind && _ids.contains(id);

  /// "Select all" would tick something more.
  bool get canSelectAll => active && _scope.any((id) => !_ids.contains(id));

  // Ticking a different kind of thing starts a new selection.
  void _use(SelectKind k) {
    if (kind == k) return;
    _ids.clear();
    _scope = const [];
    _range.clear();
    kind = k;
  }

  // The last one clicked, for Shift + click (0.1.47, range_select.dart).
  final _range = RangePicker();

  void toggle(String id, {SelectKind kind = SelectKind.songs}) {
    _use(kind);
    if (!_ids.remove(id)) _ids.add(id);
    _range.anchor = id;
    notifyListeners();
  }

  /// A click on [id] while selecting, with [order] the list it's shown in: with Shift held, ticks
  /// everything from the last one clicked to it; otherwise ticks or unticks it ([toggle]). With
  /// nothing selected yet, Shift + click starts selecting with it.
  void pick(String id, List<String> order, {SelectKind kind = SelectKind.songs}) {
    _use(kind);
    if (_ids.isEmpty && _scope.isEmpty) _scope = List.of(order);
    _range.pick(_ids, id, order);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids, {SelectKind kind = SelectKind.songs}) {
    _use(kind);
    _ids.addAll(ids);
    notifyListeners();
  }

  /// Starts selecting with [id] ticked. [scope] is everything shown alongside it
  /// (what "Select all" ticks); with [all] they're all ticked straight away.
  void start(String id, {required SelectKind kind, List<String> scope = const [], bool all = false}) {
    _use(kind);
    _scope = List.of(scope);
    _ids.add(id);
    _range.anchor = id;
    if (all) _ids.addAll(scope);
    notifyListeners();
  }

  /// Ticks everything shown where selecting started.
  void selectScope() {
    _ids.addAll(_scope);
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    _scope = const [];
    _range.clear();
    notifyListeners();
  }
}
