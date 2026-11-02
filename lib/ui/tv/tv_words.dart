// What the TV keyboard offers, depending on where it's typing (0.2.8).
//
// The user (2 Nov 2026) asked for predicted words that are "context aware" and for a review of
// where the keyboard is used. It's used on Search (the short keyboard) and by every text box on
// the TV (the full one, through TvTextField): titles and names (videos, songs, books, series,
// collections, seasons, themes, playlists), the boxes that pick from what's in the library
// (Artist, Album, Author, Genre, Category, Collection), numbers (Year, Season, Episode, a book's
// number in its series), a server's address, user name and password, descriptions and lyrics,
// bookmarks' notes, and codes (a colour, a shared theme). So the keyboard is told what it's for
// ([TvTyping], worked out from the box: its label and keyboard type) and:
//  * Search: words from everything in the library, in small letters; next words as in its names;
//  * names and titles: capitals at the start of each word by themselves (one press of Shift
//    makes the next letter small), words from the library;
//  * the pick-from-the-library boxes: also the whole names (a genre, an artist) that start with
//    what's typed;
//  * descriptions, notes and lyrics: a capital to start each sentence; words from the library and
//    words typed before;
//  * numbers: a number pad, nothing else;
//  * an address: http://, https://, the addresses of servers already set up, the usual ports;
//  * a password or a code: no predictions, nothing remembered, no capitals put in.
// Words typed in the boxes that predict are remembered on this device (tv_words.json) so they're
// offered next time; never anything typed in a password, address, user name or code box.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/storage.dart';
import '../../services/word_predictor.dart';
import '../../state/library_model.dart';
import '../../state/servers_model.dart';
import '../../state/video_library_model.dart';

/// What a box is for, which decides the keys, capitals and predictions.
enum TvTyping {
  /// The Search page: small letters, words from the whole library.
  search,

  /// A name or title: a capital at the start of each word.
  title,

  /// Picks from what's in the library (Genre, Artist…): whole names offered too.
  pick,

  /// Sentences (a description, a note, lyrics): a capital at the start of each sentence.
  sentence,

  /// Plain text with no capitals put in and nothing remembered (a user name).
  plain,

  /// Digits (Year, Season, Episode): the number pad.
  number,

  /// A web address.
  address,

  /// A password or code: no predictions, nothing remembered.
  secret;

  bool get predicts => this != number && this != secret && this != plain;
  bool get remembers => this == title || this == pick || this == sentence;
}

/// Works out what a text box is for from its [label] and keyboard settings.
TvTyping tvTypingFor({String? label, TextInputType? keyboardType, bool obscure = false, bool multiline = false}) {
  if (obscure) return TvTyping.secret;
  final l = (label ?? '').toLowerCase();
  final kind = keyboardType?.index;
  if (kind == TextInputType.number.index || kind == TextInputType.phone.index) return TvTyping.number;
  if (kind == TextInputType.url.index || l.contains('address') || l.contains('url')) return TvTyping.address;
  if (l.contains('password') || l.contains('code') || l.contains('token') || l.contains('key')) return TvTyping.secret;
  if (l.contains('user')) return TvTyping.plain;
  if (multiline || kind == TextInputType.multiline.index) return TvTyping.sentence;
  if (_pickLabels.any(l.contains)) return TvTyping.pick;
  if (l.contains('note') || l.contains('description') || l.contains('what happens')) return TvTyping.sentence;
  return TvTyping.title;
}

const _pickLabels = ['genre', 'artist', 'album', 'author', 'narrator', 'category', 'collection', 'series', 'composer'];

/// The predictor for a box labelled [label] that's for [typing], from what's in the library and
/// what was typed before. Null when it shouldn't predict.
WordPredictor? tvPredictorFor(BuildContext context, TvTyping typing, {String? label, Map<String, int> learned = const {}}) {
  if (!typing.predicts) return null;
  final lib = context.read<LibraryModel?>();
  final videos = context.read<VideoLibraryModel?>();
  final l = (label ?? '').toLowerCase();
  if (typing == TvTyping.address) {
    final servers = context.read<ServersModel?>();
    return WordPredictor(phrases: [
      for (final s in servers?.all ?? const <ServerEntry>[]) s.url,
      'http://',
      'https://',
      'http://192.168.1.',
    ]);
  }
  Iterable<String> genres() sync* {
    if (lib != null) {
      for (final t in lib.tracks) {
        if (t.genre != null) yield t.genre!;
      }
    }
    if (videos != null) {
      for (final c in videos.collections) {
        if (c.genre != null) yield c.genre!;
      }
      for (final v in videos.videos) {
        if (v.genre != null) yield v.genre!;
      }
    }
  }

  Iterable<String> everything() sync* {
    if (lib != null) {
      for (final a in lib.artists) {
        yield a.name;
      }
      for (final a in lib.albums) {
        yield a.title;
      }
      for (final t in lib.tracks) {
        yield t.title;
      }
      for (final b in lib.books) {
        yield b.title;
        yield b.author;
        if (b.series != null) yield b.series!;
      }
    }
    if (videos != null) {
      for (final c in videos.collections) {
        yield c.name;
      }
      for (final v in videos.videos) {
        if (v.title != v.collection) yield v.title;
      }
    }
  }

  // The whole names a pick box offers.
  final List<String> phrases = typing != TvTyping.pick
      ? const []
      : l.contains('genre')
          ? genres().toList()
          : l.contains('artist') || l.contains('composer')
              ? [for (final a in lib?.artists ?? const []) a.name]
              : l.contains('album')
                  ? [for (final a in lib?.albums ?? const []) a.title]
                  : l.contains('author') || l.contains('narrator')
                      ? [for (final b in lib?.books ?? const []) l.contains('narrator') ? (b.narrator ?? '') : b.author]
                      : l.contains('series')
                          ? [for (final b in lib?.books ?? const []) ?b.series]
                          : l.contains('category')
                              ? [for (final c in videos?.collections ?? const []) ?c.category]
                              : [for (final c in videos?.collections ?? const []) c.name];
  return WordPredictor(
    names: typing == TvTyping.pick ? phrases : everything(),
    phrases: phrases,
    learned: typing == TvTyping.search ? const {} : learned,
    lowerCase: typing == TvTyping.search,
  );
}

/// Words typed on this device, kept so they're offered again (tv_words.json: word → times).
class TvWordMemory {
  TvWordMemory._();
  static const file = 'tv_words.json';

  /// Most words kept (the least used go first).
  static const most = 3000;

  static Map<String, int>? _words;

  static Future<Map<String, int>> load(Storage storage) async {
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

  /// Remembers the words in [text] (typed in a box that [TvTyping.remembers]).
  static Future<void> learn(Storage storage, String text) async {
    final words = WordPredictor.wordsIn(text);
    if (words.isEmpty) return;
    final m = await load(storage);
    for (final w in words) {
      m[w] = (m[w] ?? 0) + 1;
    }
    if (m.length > most) {
      final keep = (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(most);
      _words = {for (final e in keep) e.key: e.value};
    }
    await storage.write(file, _words!);
  }

  /// For tests.
  static void forget() => _words = null;
}
