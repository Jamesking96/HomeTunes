// Words typed on the TV's keyboard, kept so they're offered again (0.2.8, tv_words.json on this
// device; see ui/tv/tv_words.dart for which boxes remember). Not in backups: it's only a
// convenience, made again by typing.
import '../services/word_predictor.dart';
import 'library_model.dart';

/// Words typed on this device, kept so they're offered again (tv_words.json: word → times).
class TypedWords {
  TypedWords._();
  static const file = 'tv_words.json';

  /// Most words kept (the least used go first).
  static const most = 3000;

  static Map<String, int>? _words;

  static Future<Map<String, int>> load(LibraryModel lib) async {
    final storage = lib.storage;
    if (_words != null) return _words!;
    final out = <String, int>{};
    try {
      final j = await storage.read(file);
      if (j is Map) {
        j.forEach((k, v) {
          if (k is String && v is int && v > 0) out[k] = v;
        });
      }
    } catch (_) {}
    return _words = out;
  }

  /// Remembers the words in [text] (typed in a box that predicts and isn't a password, an
  /// address, a user name or a code).
  static Future<void> learn(LibraryModel lib, String text) async {
    final words = WordPredictor.wordsIn(text);
    if (words.isEmpty) return;
    final m = await load(lib);
    for (final w in words) {
      m[w] = (m[w] ?? 0) + 1;
    }
    if (m.length > most) {
      final keep = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(most);
      _words = {for (final e in keep) e.key: e.value};
    }
    await lib.storage.write(file, _words!);
  }

  /// For tests.
  static void forget() => _words = null;
}
