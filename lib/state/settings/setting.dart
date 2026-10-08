// One saved setting, described once (refactor phase 3, 8 Oct 2026). Before, each setting in
// settings.json was written out in five places in LibraryModel: the field and its default, the
// reset at the start of load(), the read (with the default again), the save, and its setter. Now
// a Setting says its key, default, how it's read back (falling back to the default) and how it's
// written, and SettingsGroup (settings_groups.dart) loads, saves and resets from the list.
// No Flutter, so it's tested directly.

/// Reads values out of settings.json, falling back to the default for any value that's missing
/// or has the wrong type. Wrong types are noted in [damaged] so a copy of the file can be kept;
/// missing values are normal (a setting newer than the file) and aren't.
/// (Was LibraryModel's _Fields; unchanged.)
class SettingsReader {
  SettingsReader(this.m);
  final Map<String, dynamic> m;
  bool damaged = false;

  /// The raw value, for settings with their own checks.
  Object? operator [](String key) => m[key];

  T get<T>(String key, T fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is T) return v;
    damaged = true;
    return fallback;
  }

  /// A whole number (a hand-typed 15.0 is accepted as 15).
  int integer(String key, int fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is num && v.isFinite) return v.toInt();
    damaged = true;
    return fallback;
  }

  double number(String key, double fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is num && v.isFinite) return v.toDouble();
    damaged = true;
    return fallback;
  }

  /// A list of text values; anything else in the list is dropped (and noted).
  List<String>? strings(String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is! List) {
      damaged = true;
      return null;
    }
    final out = [for (final x in v) if (x is String) x];
    if (out.length != v.length) damaged = true;
    return out;
  }
}

/// One setting in settings.json: its [key], its default, how it's read back and written.
/// [get] / [set] reach the field in its group.
class Setting<T> {
  Setting(
    this.key, {
    required this.fallback,
    required this.read,
    required this.get,
    required this.set,
    Object? Function(T value)? write,
    this.writeIf,
  }) : _write = write;

  final String key;

  /// The default (a function, so lists and maps are fresh each time).
  final T Function() fallback;

  /// Reads the saved value, or the default.
  final T Function(SettingsReader r) read;
  final T Function() get;
  final void Function(T value) set;
  final Object? Function(T value)? _write;

  /// Written to settings.json only when this is true (some settings are left out when empty).
  final bool Function(T value)? writeIf;

  void reset() => set(fallback());
  void load(SettingsReader r) => set(read(r));
  void writeTo(Map<String, dynamic> out) {
    final v = get();
    if (writeIf != null && !writeIf!(v)) return;
    final w = _write;
    out[key] = w == null ? v : w(v);
  }

  /// An on / off setting.
  static Setting<bool> flag(String key, bool fallback, bool Function() get, void Function(bool) set) =>
      Setting<bool>(key, fallback: () => fallback, read: (r) => r.get(key, fallback), get: get, set: set);

  /// A whole number, kept between [min] and [max] when given.
  static Setting<int> whole(String key, int fallback, int Function() get, void Function(int) set, {int? min, int? max}) =>
      Setting<int>(key, fallback: () => fallback, get: get, set: set, read: (r) {
        final v = r.integer(key, fallback);
        return min != null && max != null ? v.clamp(min, max).toInt() : v;
      });

  /// A number, kept between [min] and [max] when given.
  static Setting<double> decimal(String key, double fallback, double Function() get, void Function(double) set,
          {double? min, double? max}) =>
      Setting<double>(key, fallback: () => fallback, get: get, set: set, read: (r) {
        final v = r.number(key, fallback);
        return min != null && max != null ? v.clamp(min, max).toDouble() : v;
      });

  /// A list of text values (folders, genres…).
  static Setting<List<String>> texts(
          String key, List<String> fallback, List<String> Function() get, void Function(List<String>) set) =>
      Setting<List<String>>(key,
          fallback: () => List.of(fallback), read: (r) => r.strings(key) ?? List.of(fallback), get: get, set: set);
}
