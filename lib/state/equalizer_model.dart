// The equaliser's settings (equalizer.json): on or off, which preset music
// and audiobooks use, your changes to the built-in presets and your own
// presets. The player listens to this and applies the sound live.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/eq_preset.dart';
import '../services/storage.dart';

/// What a preset is for (0.1.40 added videos).
enum EqTarget { music, books, videos }

class EqualizerModel extends ChangeNotifier {
  static const fileName = 'equalizer.json';

  final Storage storage;
  EqualizerModel(this.storage);

  /// The equaliser is switched on.
  bool enabled = false;

  /// Audiobooks use their own preset ([bookPresetId]); when off they use the music one.
  bool separateBooks = true;

  String musicPresetId = 'flat';
  String bookPresetId = 'spoken';

  /// Videos use their own preset ([videoPresetId]); when off they use the music one (0.1.40).
  bool separateVideos = true;
  String videoPresetId = 'flat';

  /// The audio engine refused the equaliser on this device (set by the player; not saved).
  bool unavailable = false;

  void reportUnavailable(bool refused) {
    if (unavailable == refused) return;
    unavailable = refused;
    notifyListeners();
  }

  // Built-in presets the user has changed, by id.
  Map<String, EqPreset> _edited = {};
  // The user's own presets, in the order they were made.
  List<EqPreset> _custom = [];
  // Saving is put off a moment while a slider is dragged.
  Timer? _saveTimer;

  /// Every preset, built-in ones first (with the user's changes).
  List<EqPreset> get presets => [for (final b in builtInEqPresets) _edited[b.id] ?? b, ..._custom];

  /// The preset with [id], or Flat if it no longer exists.
  EqPreset presetById(String id) {
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return _edited['flat'] ?? builtInEqPresets.first;
  }

  EqPreset get musicPreset => presetById(musicPresetId);
  EqPreset get bookPreset => presetById(bookPresetId);

  /// The preset chosen for music or for audiobooks (books use music's when [separateBooks] is off).
  EqPreset presetFor({required bool book}) => book && separateBooks ? bookPreset : musicPreset;

  /// What should be heard right now, or null when the equaliser is off.
  EqPreset? activeFor({required bool book}) => enabled ? presetFor(book: book) : null;

  EqPreset get videoPreset => presetById(videoPresetId);

  /// Whether [t] has a preset of its own (music always does).
  bool separate(EqTarget t) => switch (t) {
        EqTarget.music => true,
        EqTarget.books => separateBooks,
        EqTarget.videos => separateVideos,
      };

  /// The preset chosen for [t] (the music one when [t] doesn't have its own).
  EqPreset presetForTarget(EqTarget t) => !separate(t)
      ? musicPreset
      : switch (t) {
          EqTarget.music => musicPreset,
          EqTarget.books => bookPreset,
          EqTarget.videos => videoPreset,
        };

  /// What videos should sound like now, or null when the equaliser is off.
  EqPreset? get activeForVideos => enabled ? presetForTarget(EqTarget.videos) : null;

  /// A built-in preset that's been changed from how it comes.
  bool isEdited(String id) => _edited.containsKey(id);

  Future<void> load() async {
    enabled = false;
    separateBooks = true;
    musicPresetId = 'flat';
    bookPresetId = 'spoken';
    separateVideos = true;
    videoPresetId = 'flat';
    _edited = {};
    _custom = [];
    final j = await storage.read(fileName);
    // HomeTunes: a wrong type anywhere used to throw here and stop the app starting. Now each
    // value and preset is read on its own; anything damaged is skipped and a copy of the file
    // is kept before the next save replaces it.
    var damaged = j != null && j is! Map;
    T value<T>(dynamic v, T fallback) {
      if (v == null) return fallback;
      if (v is T) return v;
      damaged = true;
      return fallback;
    }

    if (j is Map) {
      enabled = value(j['enabled'], false);
      separateBooks = value(j['separateBooks'], true);
      musicPresetId = value(j['music'], 'flat');
      bookPresetId = value(j['book'], 'spoken');
      separateVideos = value(j['separateVideos'], true);
      videoPresetId = value(j['video'], 'flat');
      for (final e in value<List>(j['edited'], const [])) {
        try {
          final original = builtInEqPreset(e['id'] as String);
          if (original == null) continue;
          _edited[original.id] = EqPreset.fromJson(e as Map<String, dynamic>, builtIn: true).copyWith(name: original.name);
        } catch (_) {
          damaged = true;
        }
      }
      for (final c in value<List>(j['custom'], const [])) {
        try {
          _custom.add(EqPreset.fromJson(c as Map<String, dynamic>));
        } catch (_) {
          damaged = true;
        }
      }
    }
    if (damaged) await storage.keepCopy(fileName);
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'separateBooks': separateBooks,
        'music': musicPresetId,
        'book': bookPresetId,
        'separateVideos': separateVideos,
        'video': videoPresetId,
        'edited': [for (final p in _edited.values) p.toJson()],
        'custom': [for (final p in _custom) p.toJson()],
      };

  Future<void> _save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return storage.write(fileName, toJson());
  }

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  /// Saves any change still waiting (e.g. from a slider that was just let go).
  Future<void> flush() => _saveTimer == null ? Future.value() : _save();

  Future<void> setEnabled(bool on) async {
    enabled = on;
    notifyListeners();
    await _save();
  }

  Future<void> setSeparateBooks(bool on) async {
    separateBooks = on;
    notifyListeners();
    await _save();
  }

  Future<void> setSeparateVideos(bool on) async {
    separateVideos = on;
    notifyListeners();
    await _save();
  }

  /// Uses preset [id] for audiobooks ([forBooks]) or for music. Choosing one also switches the equaliser on.
  Future<void> choose(String id, {required bool forBooks}) =>
      chooseFor(forBooks ? EqTarget.books : EqTarget.music, id);

  /// Uses preset [id] for [t] (music's when [t] has no preset of its own). Also switches the
  /// equaliser on.
  Future<void> chooseFor(EqTarget t, String id) async {
    switch (separate(t) ? t : EqTarget.music) {
      case EqTarget.music:
        musicPresetId = id;
      case EqTarget.books:
        bookPresetId = id;
      case EqTarget.videos:
        videoPresetId = id;
    }
    enabled = true;
    notifyListeners();
    await _save();
  }

  /// Changes a preset's sliders; heard straight away, saved a moment later.
  void adjust(String id, {List<double>? gains, double? level}) {
    final p = presetById(id);
    if (p.id != id) return;
    final changed = p.copyWith(
      gains: gains == null ? null : [for (final g in gains) EqPreset.clampGain(g)],
      level: level == null ? null : EqPreset.clampLevel(level),
    );
    if (p.builtIn) {
      final original = builtInEqPreset(id)!;
      if (changed.soundsLike(original)) {
        _edited.remove(id);
      } else {
        _edited[id] = changed;
      }
    } else {
      _custom = [for (final c in _custom) c.id == id ? changed : c];
    }
    notifyListeners();
    _saveSoon();
  }

  /// Puts a built-in preset back to how it comes.
  Future<void> restoreDefault(String id) async {
    if (_edited.remove(id) == null) return;
    notifyListeners();
    await _save();
  }

  /// Puts every built-in preset back to how it comes. Your own presets are kept.
  Future<void> restoreAll() async {
    if (_edited.isEmpty) return;
    _edited = {};
    notifyListeners();
    await _save();
  }

  /// Makes a new preset of your own called [name], starting from [from]'s sliders. Returns its id.
  Future<String> addCustom(String name, {EqPreset? from}) async {
    final base = from ?? builtInEqPresets.first;
    var n = DateTime.now().microsecondsSinceEpoch;
    while (_custom.any((c) => c.id == 'my-$n')) {
      n++;
    }
    final p = EqPreset(id: 'my-$n', name: name.trim(), gains: List.of(base.gains), level: base.level);
    _custom = [..._custom, p];
    notifyListeners();
    await _save();
    return p.id;
  }

  Future<void> rename(String id, String name) async {
    if (name.trim().isEmpty) return;
    _custom = [for (final c in _custom) c.id == id ? c.copyWith(name: name.trim()) : c];
    notifyListeners();
    await _save();
  }

  /// Deletes one of your own presets. Music or books using it go back to Flat / Spoken word.
  Future<void> delete(String id) async {
    if (!_custom.any((c) => c.id == id)) return;
    _custom = [for (final c in _custom) if (c.id != id) c];
    if (musicPresetId == id) musicPresetId = 'flat';
    if (bookPresetId == id) bookPresetId = 'spoken';
    if (videoPresetId == id) videoPresetId = 'flat';
    notifyListeners();
    await _save();
  }

  @override
  void dispose() {
    if (_saveTimer != null) _save();
    super.dispose();
  }
}
