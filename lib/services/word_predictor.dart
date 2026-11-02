// Word predictions for the TV's on-screen keyboard (0.2.8).
//
// The user (2 Nov 2026): "The keypad we type on when using the application on the TV can be a
// bit time consuming… predicted words, where as you type 3/4 words that are the closest show up
// near the top… [and] context aware".
//
// A WordPredictor is made from the names that make sense where the typing is (song, album and
// video titles for Search; genres for a Genre box; …) plus words typed before. For what's typed so
// far it offers up to four words: those starting with the word being typed, the likeliest first
// (how often the word comes up, more when it follows the word before it in a name, as "king"
// follows "lion"); after a space, the words that most often come next; and, when nothing starts
// that way, words one slip away ("lino" → "lion"). [phrases] (a Genre or Category box) also
// offers whole names that start with everything typed.
//
// Nothing here knows about Flutter: the keyboard (ui/tv/tv_keyboard.dart) and where its words come
// from (ui/tv/tv_words.dart) use it.
import 'dart:math' as math;

/// One prediction: [text] puts [word] in place of what's being typed ([whole]: the whole box).
class Prediction {
  final String word;
  final bool whole;
  const Prediction(this.word, {this.whole = false});

  @override
  bool operator ==(Object other) => other is Prediction && other.word == word && other.whole == whole;
  @override
  int get hashCode => Object.hash(word, whole);
  @override
  String toString() => whole ? '[$word]' : word;
}

class WordPredictor {
  /// [names]: titles and names (each split into words). [learned]: words typed before and how
  /// many times. [phrases]: whole names offered as they are (a Genre box's genres). [lowerCase]:
  /// words offered in small letters (Search).
  WordPredictor({
    Iterable<String> names = const [],
    Map<String, int> learned = const {},
    Iterable<String> phrases = const [],
    this.lowerCase = false,
    this.sentenceCase = false,
  }) {
    for (final n in names) {
      _addName(n, 1);
    }
    learned.forEach((w, n) {
      if (n > 0) _addWord(w, n * _learnedWeight);
    });
    final seen = <String>{};
    for (final p in phrases) {
      final t = p.trim();
      if (t.isNotEmpty && seen.add(t.toLowerCase())) _phrases.add(t);
    }
    _keys = _words.keys.toList()..sort();
  }

  final bool lowerCase;

  /// Sentences (a description): a word that's only capitalised because it was in a title
  /// ("Movie") is offered small mid-sentence, unless the typing started with a capital.
  final bool sentenceCase;

  /// A word typed before counts as much as this many names using it.
  static const _learnedWeight = 3;

  /// How much more a word counts when it follows the word before it in a name.
  static const _followWeight = 6;

  // lower-case word → its usual spelling and how often it comes up.
  final _words = <String, ({String shown, int count})>{};
  // lower-case word → the words after it, and how often.
  final _next = <String, Map<String, int>>{};
  final _phrases = <String>[];
  late List<String> _keys;

  int get size => _words.length;

  static final _split = RegExp(r'\s+');

  /// The word with leading and trailing punctuation taken off ("(1994)" → "1994", "king," →
  /// "king"); empty when nothing's left.
  static String clean(String w) {
    var s = 0, e = w.length;
    bool keep(int c) => _isWordChar(c);
    while (s < e && !keep(w.codeUnitAt(s))) {
      s++;
    }
    while (e > s && !keep(w.codeUnitAt(e - 1))) {
      e--;
    }
    return w.substring(s, e);
  }

  static bool _isWordChar(int c) =>
      (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c > 127;

  void _addName(String name, int weight) {
    String? before;
    for (final raw in name.split(_split)) {
      final w = clean(raw);
      if (w.isEmpty) {
        before = null;
        continue;
      }
      _addWord(w, weight);
      final k = w.toLowerCase();
      if (before != null) {
        final m = _next.putIfAbsent(before, () => {});
        m[k] = (m[k] ?? 0) + weight;
      }
      before = k;
    }
  }

  void _addWord(String w, int weight) {
    final k = w.toLowerCase();
    final had = _words[k];
    // The spelling seen most (or first) is the one offered: "iPhone", "AC/DC".
    _words[k] = had == null ? (shown: w, count: weight) : (shown: had.shown, count: had.count + weight);
  }

  /// Up to [max] predictions for [text] (everything in the box so far).
  List<Prediction> predict(String text, {int max = 4}) {
    final endsInSpace = text.isEmpty || text.endsWith(' ') || text.endsWith('\n');
    final parts = text.trimRight().split(_split).where((w) => w.isNotEmpty).toList();
    final typing = endsInSpace ? '' : (parts.isEmpty ? '' : parts.removeLast());
    final partial = clean(typing).toLowerCase();
    final before = parts.isEmpty ? null : clean(parts.last).toLowerCase();
    final follows = before == null ? const <String, int>{} : (_next[before] ?? const <String, int>{});
    final out = <Prediction>[];
    final taken = <String>{};

    void add(String word, {bool whole = false}) {
      final k = word.toLowerCase();
      if (out.length >= max || !taken.add(k)) return;
      out.add(Prediction(_style(word, typing), whole: whole));
    }

    // Whole names that start with everything typed (a genre, a category).
    final all = text.trim().toLowerCase();
    if (_phrases.isNotEmpty) {
      final matches = [
        for (final p in _phrases)
          if (all.isEmpty || (p.toLowerCase().startsWith(all) && p.toLowerCase() != all)) p
      ]..sort((a, b) => a.length != b.length ? a.length.compareTo(b.length) : a.toLowerCase().compareTo(b.toLowerCase()));
      for (final p in matches.take(max)) {
        if (out.length >= max) break;
        // One word that's also a whole name ("Action") is offered once.
        if (taken.add(p.toLowerCase())) out.add(Prediction(p, whole: true));
      }
    }

    if (partial.isEmpty) {
      if (typing.isNotEmpty) return out; // only punctuation so far
      // After a space: what usually comes next.
      final ranked = follows.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in ranked) {
        add(_words[e.key]?.shown ?? e.key);
      }
      return out;
    }

    int score(String k) => _words[k]!.count + _followWeight * (follows[k] ?? 0);

    // Starting with what's typed.
    final starts = <String>[];
    for (var i = _lowerBound(partial); i < _keys.length && _keys[i].startsWith(partial); i++) {
      if (_keys[i] != partial) starts.add(_keys[i]);
    }
    starts.sort((a, b) {
      final s = score(b).compareTo(score(a));
      return s != 0 ? s : (a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b));
    });
    for (final k in starts) {
      add(_words[k]!.shown);
    }
    // Nothing starts that way: words one slip away (a key next to the right one, a letter missed
    // or doubled, two swapped).
    if (starts.isEmpty && partial.length >= 3) {
      final near = <String>[];
      for (final k in _keys) {
        if (k.length + 1 < partial.length || k == partial || taken.contains(k)) continue;
        if (_slips(partial, k.substring(0, math.min(k.length, partial.length + 1))) <= 1) near.add(k);
      }
      near.sort((a, b) => score(b).compareTo(score(a)));
      for (final k in near) {
        add(_words[k]!.shown);
      }
    }
    return out;
  }

  /// [word] spelt the way the box needs: small letters for Search; a capital when the typing
  /// started with one.
  String _style(String word, String typing) {
    if (lowerCase) return word.toLowerCase();
    final capital = typing.isNotEmpty && _isUpper(typing[0]);
    if (capital && !_isUpper(word[0])) return word[0].toUpperCase() + word.substring(1);
    if (sentenceCase && !capital && word.length > 1 && _isUpper(word[0]) && word.substring(1) == word.substring(1).toLowerCase()) {
      return word.toLowerCase();
    }
    return word;
  }

  static bool _isUpper(String c) => c != c.toLowerCase() && c == c.toUpperCase();

  int _lowerBound(String s) {
    var lo = 0, hi = _keys.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_keys[mid].compareTo(s) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// How many slips turn [typed] into the start of a word [start] (one letter wrong, missed,
  /// added, or two swapped count one each); stops counting at 2.
  static int _slips(String typed, String start) {
    // The typed letters against the word's start, with one letter more or less allowed.
    int best = 2;
    for (final len in [typed.length - 1, typed.length, typed.length + 1]) {
      if (len <= 0 || len > start.length) continue;
      final d = _distance(typed, start.substring(0, len));
      if (d < best) best = d;
    }
    return best;
  }

  /// Damerau–Levenshtein distance (optimal string alignment), capped at 2.
  static int _distance(String a, String b) {
    if ((a.length - b.length).abs() > 1) return 2;
    final m = a.length, n = b.length;
    var prev2 = List<int>.filled(n + 1, 0);
    var prev = List<int>.generate(n + 1, (j) => j);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0)..[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost);
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = math.min(v, prev2[j - 2] + 1);
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin >= 2) return 2;
      prev2 = prev;
      prev = cur;
    }
    return math.min(prev[n], 2);
  }

  /// [text] with [p] put in: the word being typed (or, after a space, a new word) becomes
  /// [p]'s word, then a space; a whole-box prediction replaces everything.
  static String apply(String text, Prediction p) {
    if (p.whole) return p.word;
    final endsInSpace = text.isEmpty || text.endsWith(' ') || text.endsWith('\n');
    if (endsInSpace) return '$text${p.word} ';
    final cut = math.max(text.lastIndexOf(' '), text.lastIndexOf('\n'));
    return '${text.substring(0, cut + 1)}${p.word} ';
  }

  /// The words in [text] worth remembering (for [learned]): two letters or more, not numbers.
  static List<String> wordsIn(String text) => [
        for (final raw in text.split(_split))
          if (clean(raw).length >= 2 && int.tryParse(clean(raw)) == null) clean(raw)
      ];
}
