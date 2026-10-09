// Part of PlayerModel (refactor phase 11, 9 Oct 2026: player_model.dart was over 1,000 lines).
// Audiobooks: playing one (from the saved place, with the rewind after a break), saving the place, the
// music queue that waits while a book plays, skipping across files, chapters and speed.
part of '../player_model.dart';

extension PlayerBooks on PlayerModel {
  /// Plays [b] from where the listener left off, or from [partIndex]/[at] if
  /// given (e.g. a chapter), or from the start with [fromStart].
  Future<void> playBook(Book b, {bool fromStart = false, int? partIndex, Duration? at}) async {
    if (b.parts.isEmpty) return;
    // 1. Put away what was playing: save the old book's place, or park the music queue
    //    (songs, place, shuffle, repeat) so "Back to music" can bring it back.
    if (book != null) {
      saveBookPlace();
    } else if (!queue.isEmpty) {
      _music = _MusicQueue(
        queue.tracks,
        queue.originalTracks,
        queue.position,
        _player.position,
        queue.shuffle,
        queue.repeat,
        queue.contextLabel,
      );
    }

    // 2. Work out where to start: a chosen file/position, or the saved place, or the start.
    var index = 0;
    var position = Duration.zero;
    if (partIndex != null) {
      index = partIndex.clamp(0, b.parts.length - 1);
      position = at ?? Duration.zero;
    } else if (!fromStart) {
      final saved = listening?.progressFor(b);
      if (saved != null && !saved.finished) {
        final i = b.indexOfPart(saved.partId);
        if (i >= 0) {
          index = i;
          // Go back a little when resuming (if that setting is on), more after a longer break.
          final since = Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - saved.updatedMs);
          position = library.settings.listening.rewindOnResume ? saved.position - PlayerModel.resumeRewind(since) : saved.position;
          if (position.isNegative) position = Duration.zero;
        }
      }
    }

    // 3. Switch into book mode: the queue becomes the book's files, in order, with no repeat.
    _setBook(b);
    queue.setTracks(b.parts, start: index, shuffle: false, label: 'Book · ${b.title}');
    queue.repeat = RepeatSetting.off;
    // 4. Save the starting place, set the book's own speed, and start playing.
    await listening?.record(b, b.parts[index].id, position);
    await _applySpeed(listening?.speedFor(b) ?? library.settings.listening.defaultBookSpeed);
    await _openCurrent(startAt: position);
  }

  /// Stops being in book mode (music was chosen). The waiting music queue is
  /// dropped because new music replaces it, but its shuffle/repeat are kept.
  void _leaveBook() {
    if (book == null) return;
    saveBookPlace();
    _setBook(null);
    _applySpeed(1.0);
    final m = _music;
    if (m != null) {
      queue.shuffle = m.shuffle;
      queue.repeat = m.repeat;
    }
    _music = null;
  }

  /// "Play next" / "Add to queue" while a book plays: the song joins the waiting music queue
  /// instead of interrupting the book. [next] puts it after the song that was playing.
  void _addToWaitingMusic(Track t, {required bool next}) {
    final m = _music;
    if (m == null || m.tracks.isEmpty) {
      _music = _MusicQueue([t], [t], 0, Duration.zero, queue.shuffle, RepeatSetting.off, null);
    } else {
      final list = List.of(m.tracks);
      list.insert(next ? m.index + 1 : list.length, t);
      // Same place in the original order: after the song that was playing, or at the end.
      final original = List.of(m.original);
      final at = next ? original.indexOf(m.tracks[m.index]) + 1 : original.length;
      original.insert(at.clamp(0, original.length), t);
      _music = _MusicQueue(list, original, m.index, m.position, m.shuffle, m.repeat, m.label);
    }
    _changed();
  }

  /// Leaves the book (its place is saved) and goes back to the music queue.
  Future<void> resumeMusic() async {
    final m = _music;
    if (book == null || m == null) return;
    saveBookPlace();
    _setBook(null);
    await _applySpeed(1.0);
    _music = null;
    // Put the queue back exactly: play order, original order (for turning shuffle off later),
    // place, shuffle and repeat.
    queue.restore(m.tracks, m.original, position: m.index, shuffle: m.shuffle, repeat: m.repeat, label: m.label);
    await _openCurrent(startAt: m.position);
  }

  // ---- skipping, chapters and speed ----

  /// The chapter playing now, or null for music.
  BookChapter? get currentChapter {
    final i = currentChapterIndex;
    return i < 0 ? null : _chapters[i];
  }

  /// Goes to [at] in file [part] of the queue (same file: just seeks).
  Future<void> _goTo(int part, Duration at) async {
    if (at.isNegative) at = Duration.zero;
    // Same file: a plain seek. Another file: open that file at the right spot.
    if (part == queue.position) {
      await _player.seek(at);
      _changed();
    } else {
      queue.jumpTo(part);
      await _openCurrent(startAt: at);
    }
    // Save the new place straight away, so a jump isn't lost if the app closes.
    final b = book;
    final t = queue.current;
    if (b != null && t != null) await listening?.record(b, t.id, at);
  }

  /// Jumps back or forward by [delta]. In a book this carries on into the
  /// previous / next file.
  Future<void> skipBy(Duration delta) async {
    final t = current;
    if (t == null) return;
    final b = book;
    // The engine's length is best for the file that's open; the others use their tagged length.
    final length = duration > Duration.zero ? duration : t.duration;
    final lengths = b == null
        ? [length]
        : [for (var i = 0; i < b.parts.length; i++) i == queue.position ? length : b.parts[i].duration];
    final target = PlayerModel.skipTarget(lengths, b == null ? 0 : queue.position, position, delta);
    if (target == null) return next(); // past the end of a song: next song
    await _goTo(b == null ? queue.position : target.$1, target.$2);
  }

  // The skip amounts come from Settings → Audiobooks (15 s back and 30 s forward by default).
  Future<void> skipBack() => skipBy(-Duration(seconds: library.settings.listening.skipBackSeconds));

  Future<void> skipForward() => skipBy(Duration(seconds: library.settings.listening.skipForwardSeconds));

  /// Goes to [at] in file [part] of the playing book (e.g. a bookmark).
  Future<void> goToPart(int part, Duration at) => _goTo(part, at);

  /// Jumps to the start of chapter [i] of the playing book.
  Future<void> goToChapter(int i) async {
    if (i < 0 || i >= _chapters.length) return;
    await _goTo(_chapters[i].part, _chapters[i].start);
  }

  /// Jumps to the start of the next chapter (does nothing in the last one).
  Future<void> nextChapter() async {
    final i = currentChapterIndex;
    if (i < 0 || i + 1 >= _chapters.length) return;
    final c = _chapters[i + 1];
    await _goTo(c.part, c.start);
  }

  /// Back to the start of this chapter, or to the previous one if we're
  /// within 3 seconds of the start.
  Future<void> previousChapter() async {
    final i = currentChapterIndex;
    if (i < 0) return;
    final c = _chapters[i];
    final into = bookOffset - c.offset;
    final target = (into > const Duration(seconds: 3) || i == 0) ? c : _chapters[i - 1];
    await _goTo(target.part, target.start);
  }

  // Sets the engine's speed without remembering it for the book.
  Future<void> _applySpeed(double s) async {
    speed = s;
    await _player.setRate(s);
  }

  /// Changes the speed; for a book it's remembered for that book.
  Future<void> setSpeed(double s) async {
    await _applySpeed(s);
    final b = book;
    if (b != null) await listening?.setSpeed(b, s);
    _changed();
  }
}
