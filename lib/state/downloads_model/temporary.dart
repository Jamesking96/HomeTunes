// Temporary copies (0.2.4, step 4 of the Servers & Downloads plan). Part of downloads_model.dart.
//
// The user asked (25 Oct) for "a new setting to the servers tab in the settings, this should be
// for allowing us to temporarily download the streamed content and play it, removing it after a
// period of time after it's been watched (this is separate to pre-downloading the content from
// the server, but add another toggle that says to turn off the auto delete)". The plan:
//  * Save a copy while streaming (off to start with): a server song, audiobook file or video
//    that starts playing is saved in the background, as a download whose origin is temporary,
//    and plays from here next time.
//  * Delete after 1, 3, 7 (to start with) or 30 days after it's finished: a video watched, a
//    song played through (PlayerModel.onPlayedThrough), or its audiobook finished. Something only
//    part-played stays until it's finished or the space runs out.
//  * Don't delete automatically: nothing is cleared by itself; once the space is full, nothing
//    more is saved.
//  * Space for temporary copies (10 GB to start with), apart from the downloads' own limit: when
//    it's full, the oldest finished copies go first, then the oldest part-played ones.
//  * Clear now removes every temporary copy. Keep turns one into a normal download.
part of '../downloads_model.dart';

const _day = 24 * 60 * 60 * 1000;

extension TemporaryCopies on DownloadsModel {
  /// Whether [id] is here as a temporary copy (for the Source mark's clock).
  bool isTemporaryCopy(String id) {
    final e = _entries[id];
    return e != null && e.isTemporary && e.isDone && e.file != null;
  }

  /// How many temporary copies are here.
  int get temporaryCount => temporaries.length;

  /// A server song or audiobook file started playing (main.dart follows the player): save a
  /// copy of it, when that's switched on.
  void startedPlaying(Track t) {
    if (t.isLocal) return;
    _saveTemporary(DownloadItem.track(t, book: library.bookOfTrack(t.id) != null));
  }

  /// A song played through to its end (PlayerModel.onPlayedThrough): a temporary copy of it is
  /// finished. (An audiobook's files are finished with the book.)
  void playedThrough(Track t) {
    final e = _entries[t.id];
    if (e == null || !e.isTemporary || e.book) return;
    _entries[t.id] = e.copyWith(finishedMs: now());
    _saveSoon();
  }

  /// Keep: these temporary copies become normal downloads (never cleared by themselves).
  Future<void> keepCopies(Iterable<String> ids) async {
    var changed = false;
    for (final id in ids) {
      final e = _entries[id];
      if (e == null || !e.isTemporary) continue;
      _entries[id] = e.copyWith(origin: DownloadOrigin.manual, clearFinished: true);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _save();
  }

  /// Clear now: every temporary copy goes (and any being saved stops).
  Future<void> clearTemporary() => remove([for (final e in _entries.values) if (e.isTemporary) e.id]);

  /// "Temporary copy, cleared in 2 days", "…cleared 7 days after it's finished", "…kept until
  /// you clear it".
  String temporaryNote(DownloadEntry e) {
    if (tempKeep) return 'Temporary copy, kept until you clear it';
    final f = e.finishedMs;
    if (f == null) return 'Temporary copy, cleared $tempDays day${tempDays == 1 ? '' : 's'} after it\'s finished';
    final left = ((f + tempDays * _day - now()) / _day).ceil();
    return left <= 0 ? 'Temporary copy, cleared soon' : 'Temporary copy, cleared in $left day${left == 1 ? '' : 's'}';
  }

  // A server video started playing (VideoLibraryModel.onServerVideoStarted): the next episodes,
  // and a temporary copy of this one.
  void _serverVideoStarted(VideoItem v) {
    _downloadAhead(v);
    _saveTemporary(DownloadItem.video(v));
  }

  void _saveTemporary(DownloadItem it) {
    if (!tempSave || _entries.containsKey(it.id)) return;
    if (!isRemoteVideoId(it.id) && !it.id.startsWith('server:')) return;
    download([it], const DownloadQuality.original(), origin: DownloadOrigin.temporary);
  }

  /// Clears finished copies whose days are up, notes which have just been finished (videos
  /// watched, books finished; a video marked not watched again isn't finished any more), and
  /// keeps them within their space.
  void _tidyTemporary() {
    var changed = false;
    final t = now();
    for (final e in [..._entries.values]) {
      if (!e.isTemporary) continue;
      final finished = switch (e.kind) {
        DownloadKind.video => videos.placeOf(e.id)?.watched ?? false,
        DownloadKind.song when e.book => _bookFinished(e.id),
        DownloadKind.song => e.finishedMs != null,
      };
      if (finished && e.finishedMs == null) {
        _entries[e.id] = e.copyWith(finishedMs: t);
        changed = true;
      } else if (!finished && e.finishedMs != null && (e.kind == DownloadKind.video || e.book)) {
        _entries[e.id] = e.copyWith(clearFinished: true);
        changed = true;
      }
    }
    final gone = <String>[];
    if (!tempKeep) {
      for (final e in _entries.values) {
        final f = e.finishedMs;
        if (e.isTemporary && f != null && t - f >= tempDays * _day && !_playingNow(e.id)) gone.add(e.id);
      }
    }
    if (gone.isNotEmpty) {
      _dropTemporary(gone);
      changed = true;
    }
    // Over the space (the limit was lowered, or a copy came out bigger than expected).
    if (!tempKeep && tempUsedBytes > tempLimitBytes) {
      _dropTemporary(_idsToFree(_clearOrder(), tempUsedBytes - tempLimitBytes));
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _saveSoon();
    }
  }

  bool _bookFinished(String trackId) {
    final b = library.bookOfTrack(trackId);
    final l = listening;
    return b != null && l != null && l.stateOf(b) == BookState.finished;
  }

  /// The temporary copies here in the order they'd be cleared to make room: finished ones
  /// (longest finished first), then part-played ones (oldest first).
  ///
  /// Never one that's playing now ([inUse]; 0.2.5): making room for a new copy could delete the
  /// file of the one on screen, and its next jump or resume would fail.
  List<DownloadEntry> _clearOrder() {
    final here = [for (final e in _entries.values) if (e.isTemporary && e.isDone && !_playingNow(e.id)) e];
    final finished = [for (final e in here) if (e.finishedMs != null) e]
      ..sort((a, b) => a.finishedMs!.compareTo(b.finishedMs!));
    final partPlayed = [for (final e in here) if (e.finishedMs == null) e]
      ..sort((a, b) => (a.doneMs ?? a.addedMs).compareTo(b.doneMs ?? b.addedMs));
    return [...finished, ...partPlayed];
  }

  bool _playingNow(String id) => inUse?.call(id) ?? false;

  /// Makes room for temporary copy [e] by clearing older ones. False when it can't (Don't delete
  /// automatically is on, or there isn't enough to clear).
  bool _makeTemporaryRoom(DownloadEntry e) {
    if (tempKeep) return false;
    final need = e.expected ?? 0;
    if (need > tempLimitBytes) return false;
    var taken = 0;
    for (final x in _entries.values) {
      if (x.id == e.id || !x.isTemporary) continue;
      taken += x.isDone ? x.bytes : (_inEngine.contains(x.id) ? (x.expected ?? x.bytes) : 0);
    }
    final over = taken + need - tempLimitBytes;
    if (over <= 0) return true;
    final order = [for (final x in _clearOrder()) if (x.id != e.id) x];
    if (order.fold<int>(0, (s, x) => s + x.bytes) < over) return false;
    _dropTemporary(_idsToFree(order, over));
    return true;
  }

  /// The ids from the start of [order] that add up to at least [bytes].
  static List<String> _idsToFree(List<DownloadEntry> order, int bytes) {
    final out = <String>[];
    var freed = 0;
    for (final e in order) {
      if (freed >= bytes) break;
      out.add(e.id);
      freed += e.bytes;
    }
    return out;
  }

  /// Deletes temporary copies [ids] (they stream again), without remembering them as skipped.
  void _dropTemporary(Iterable<String> ids) {
    for (final id in ids.toList()) {
      final e = _entries.remove(id);
      if (e == null) continue;
      if (_inEngine.remove(id)) unawaited(engine.cancel(DownloadsModel.taskIdFor(id)));
      _jobs.remove(id);
      _requests.remove(id);
      DownloadsModel._deleteFiles(e.file, e.subtitles);
    }
  }
}
