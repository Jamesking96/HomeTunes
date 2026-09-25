// The equaliser's settings (equalizer.json): on or off, which preset music
// and audiobooks use, your changes to the built-in presets and your own
// presets. The player listens to this and applies the sound live.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/eq_preset.dart';
import '../services/storage.dart';

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

  /// A built-in preset that's been changed from how it comes.
  bool isEdited(String id) => _edited.containsKey(id);

  Future<void> load() async {
    enabled = false;
    separateBooks = true;
    musicPresetId = 'flat';
    bookPresetId = 'spoken';
    _edited = {};
    _custom = [];
    final j = await storage.read(fileName) as Map<String, dynamic>?;
    if (j != null) {
      enabled = (j['enabled'] as bool?) ?? false;
      separateBooks = (j['separateBooks'] as bool?) ?? true;
      musicPresetId = (j['music'] as String?) ?? 'flat';
      bookPresetId = (j['book'] as String?) ?? 'spoken';
      for (final e in (j['edited'] as List? ?? const [])) {
        if (e is! Map<String, dynamic> || builtInEqPreset(e['id'] as String? ?? '') == null) continue;
        final original = builtInEqPreset(e['id'] as String)!;
        _edited[original.id] = EqPreset.fromJson(e, builtIn: true).copyWith(name: original.name);
      }
      for (final c in (j['custom'] as List? ?? const [])) {
        if (c is Map<String, dynamic> && c['id'] is String) _custom.add(EqPreset.fromJson(c));
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'separateBooks': separateBooks,
        'music': musicPresetId,
        'book': bookPresetId,
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

  /// Uses preset [id] for audiobooks ([forBooks]) or for music. Choosing one also switches the equaliser on.
  Future<void> choose(String id, {required bool forBooks}) async {
    if (forBooks) {
      bookPresetId = id;
    } else {
      musicPresetId = id;
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
    notifyListeners();
    await _save();
  }

  @override
  void dispose() {
    if (_saveTimer != null) _save();
    super.dispose();
  }
}
