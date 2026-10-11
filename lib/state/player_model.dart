// The player: joins HomeTunes' own play queue to the audio engine (media_kit, which uses mpv).
//
// Screens call methods here (play, next, skipBy, playBook…) and watch it to redraw the player
// bar and Now Playing. The play order lives in PlayQueue; this class tells the engine what to
// play. Main ideas:
// - Gapless: the engine only ever holds the current song plus the next one loaded ahead, and we
//   catch our queue up when the engine moves on by itself (see _engineIds / _onEngineAdvanced).
// - Book mode: while an audiobook plays, the queue holds the book's files, the place is saved
//   regularly (ListeningModel), and any music queue waits in _music until "Back to music".
// - It implements SleepTarget so the sleep timer can read the position and pause it.
// Refactor phase 11 (9 Oct 2026): the audiobook methods, the queue buttons and the stall check are
// extensions in player_model/ (part files of this library, so they use its private names).
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
// The engine is an AudioEngine (refactor phase 4): media_kit in the app, a fake in tests.
import '../services/engine/audio_chain.dart';
import '../services/engine/audio_engine.dart';
import '../services/engine/media_kit_audio_engine.dart';

import '../models/book.dart';
import '../models/track.dart';
import '../models/volume_boost.dart';
import '../services/playback_log.dart';
import '../services/subsonic_client.dart' show hideSecrets;
import 'equalizer_model.dart';
import 'library_model.dart';
import 'listening_model.dart';
import 'play_queue.dart';
import 'playback_guard.dart';
import 'sleep_timer.dart';
part 'player_model/books.dart';
part 'player_model/queue_actions.dart';
part 'player_model/stall_check.dart';

/// The music queue, kept aside while an audiobook plays.
// A snapshot of the queue (songs, place, shuffle/repeat, label) so it can be put back exactly.
// (0.1.15: the original order is kept too, so shuffle can be turned off properly afterwards.)
class _MusicQueue {
  final List<Track> tracks; // play order
  final List<Track> original; // the order they were queued in
  final int index;
  final Duration position;
  final bool shuffle;
  final RepeatSetting repeat;
  final String? label;
  const _MusicQueue(this.tracks, this.original, this.index, this.position, this.shuffle, this.repeat, this.label);
}

/// Connects the [PlayQueue] to the actual audio engine (media_kit / libmpv).
///
/// Position is exposed as a stream so the seek bar can update several times a
/// second without rebuilding the whole app.
class PlayerModel extends ChangeNotifier implements SleepTarget {
  final LibraryModel library;

  /// Remembers the place in audiobooks (null in tests that don't need it).
  final ListeningModel? listening;

  /// The equaliser settings (null in tests that don't need them).
  final EqualizerModel? equalizer;
  // The audio engine (media_kit / libmpv in the app; there's only ever one). Tests pass a fake.
  final AudioEngine _player;
  final PlayQueue queue = PlayQueue();
  // Our listeners on the engine's event streams, cancelled in dispose().
  final List<StreamSubscription> _subs = [];

  @override
  bool playing = false;
  // True while the engine is waiting for data (e.g. a slow server stream).
  bool buffering = false;
  // Length of the current song/file as the engine reports it.
  @override
  Duration duration = Duration.zero;
  @override
  double volume = 100; // 0–100, as the listener set it (before the equaliser's overall level)
  // The equaliser: its filter goes to the engine, its overall level turns the volume down
  // (services/engine/audio_chain.dart, shared with the video page).
  late final AudioChain _eq = AudioChain(
    preset: () => equalizer?.activeFor(book: book != null),
    hasOptions: () => _player.hasOptions,
    setOption: _player.setOption,
    level: EqLevel.volumeFactor,
    onLevelFactor: (_) => _sendVolume(),
    onResult: (refused) => equalizer?.reportUnavailable(refused),
    logChanges: true,
  );
  // A message about the last thing that went wrong (a skipped song, an engine error), or null.
  String? lastError;

  /// How many opens are in flight (see the `completed` listener).
  int _opening = 0;

  /// Gapless playback: the audio engine holds the song playing now and,
  /// loaded ahead, the one that plays next ([_engineIds], by track id). When
  /// it moves on by itself there's no gap; HomeTunes then catches its own
  /// queue up and loads the following song. HomeTunes' queue stays in charge
  /// (shuffle, repeat, Play next…): the engine never holds more than that.
  List<String> _engineIds = [];

  /// Our own changes to the engine's list are in progress (ignore its events).
  int _engineEdits = 0;

  /// Engine settings last applied (so they're only sent when they change).
  String? _appliedReplayGain;
  // The engine's volume limit has been raised for the volume boost (0.1.61).
  bool _volumeMaxRaised = false;
  bool? _appliedGapless;
  bool? _appliedLoopOne;
  bool _videoOff = false;

  /// The audiobook playing, or null when playing music.
  Book? get book => _book;
  Book? _book;

  /// The playing book's chapters (cached; empty for music).
  List<BookChapter> get chapters => _chapters;
  List<BookChapter> _chapters = const [];

  // Sets the book and caches its chapter list (worked out once, not on every redraw).
  void _setBook(Book? b) {
    final switching = (_book == null) != (b == null);
    _book = b;
    _chapters = b?.chapters ?? const [];
    // Music and audiobooks can have different equaliser presets.
    if (switching) _applyEqualizer();
  }

  /// Playback speed (1.0 = normal).
  double speed = 1.0;

  /// The listener paused (or the sleep timer, or the queue/book ended), as opposed to the engine
  /// stopping by itself for a moment while a file opens. The system media controls are told
  /// about a pause at once only when this is true (see [SystemPlayingState]).
  bool pausedOnPurpose = true;

  // Watches for playback that has quietly stopped (see [StallDetector]).
  final StallDetector _stall = StallDetector();
  Timer? _watchdog;
  DateTime? _lastRestart;

  /// The music queue waiting while a book plays.
  _MusicQueue? _music;
  // Saves the book place every 10 seconds (see the constructor).
  Timer? _saveTimer;

  PlayerModel(this.library, {this.listening, this.equalizer, AudioEngine? engine})
      : _player = engine ?? MediaKitAudioEngine() {
    library.addListener(_onLibraryChanged);
    // Gapless, ReplayGain and the volume boost's top (Settings › Playback); LibraryModel doesn't
    // pass these changes on since refactor phase 9.
    library.settings.playback.addListener(_applyEngineSettings);
    equalizer?.addListener(_applyEqualizer);
    _applyEngineSettings();
    _applyEqualizer();
    // While a book plays, save the place every 10 seconds.
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (book != null && playing) saveBookPlace();
    });
    // Every few seconds, check that "playing" really means the position is moving.
    _watchdog = Timer.periodic(const Duration(seconds: 3), (_) => _checkProgress());
    // Listen to the engine's events and copy them into our own fields for the UI.
    _subs.addAll([
      _player.playingStream.listen((v) {
        // Going from playing to paused is a good moment to save the book place.
        final paused = playing && !v;
        if (v != playing) {
          PlaybackLog.add(v
              ? 'Playing'
              : (_opening > 0 ? 'Paused for a moment while opening a file' : 'Paused${pausedOnPurpose ? '' : ' (not asked for)'}'));
        }
        playing = v;
        if (paused) saveBookPlace();
        notifyListeners();
      }),
      _player.bufferingStream.listen((v) {
        buffering = v;
        notifyListeners();
      }),
      _player.durationStream.listen((v) {
        // The engine knows the real length once a file opens; remember it if the tags were wrong.
        duration = v;
        _learnDuration(v);
        notifyListeners();
      }),
      _player.completedStream.listen((done) {
        // The engine reports "finished" at the end of every song, a moment
        // before it moves on to one loaded ahead (checked with
        // tool/bench/engine_test.dart). Only act when nothing was loaded
        // ahead: the queue ended, or gapless is off. Opening a new file can
        // also briefly report the old one as finished; ignore that too.
        // An empty engine (stopped because nothing could be played) never moves the queue on:
        // otherwise a queue of unplayable songs with repeat on could keep skipping for ever.
        if (done && _opening == 0 && _engineEdits == 0 && _engineIds.length == 1) _advance(auto: true);
      }),
      _player.indexStream.listen((index) {
        // The engine moved on to the song loaded ahead, by itself.
        if (_opening == 0 && _engineEdits == 0 && index == 1 && _engineIds.length > 1) {
          _onEngineAdvanced();
        }
      }),
      // Equaliser bands above half the file's sample rate are left out.
      _player.sampleRateStream.listen(_eq.sampleRateChanged),
      _player.errorStream.listen((e) {
        // Engine errors can quote the stream address, login token included: hide it (0.1.17).
        lastError = hideSecrets(e);
        notifyListeners();
      }),
    ]);
  }

  /// Keeps the queue (and the now-playing display / system media controls)
  /// showing songs' latest details after they're edited or rescanned.
  void _onLibraryChanged() {
    var changed = queue.refresh(library.byId);
    // Keep the playing book's details (and parts) current after a rescan.
    final b = book;
    final t = queue.current;
    if (b != null && t != null) {
      final fresh = library.bookOfTrack(t.id);
      if (fresh != null && !identical(fresh, b)) {
        _setBook(fresh);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// When a song's file didn't say how long it is (or said something wrong),
  /// remember the real length the player found, so lists and totals show it.
  ///
  /// HomeTunes (0.1.16): the engine's "length" event could arrive just as it moved on to the
  /// song loaded ahead, before HomeTunes' queue caught up, so the next song's length was saved
  /// onto the previous one. Now the length is read a few seconds later, and only if the engine
  /// and the queue still agree on which song is playing.
  void _learnDuration(Duration d) {
    final t = queue.current;
    if (t == null || d <= Duration.zero) return;
    final id = t.id;
    _learnTimer?.cancel();
    _learnTimer = Timer(const Duration(seconds: 3), () {
      final now = queue.current;
      final settled = now != null &&
          now.id == id &&
          _opening == 0 &&
          _engineEdits == 0 &&
          _engineIds.isNotEmpty &&
          _engineIds.first == id &&
          _player.index == 0;
      if (!settled) return;
      final length = _player.duration;
      if (length <= Duration.zero) return;
      // Ignore tiny differences (under 2 s) so we don't rewrite the library for nothing.
      if (!now.hasDuration || (length - now.duration).abs() > const Duration(seconds: 2)) {
        library.learnDuration(id, length);
      }
    });
  }

  Timer? _learnTimer;

  @override
  Track? get current => queue.current;
  // The seek bar listens to this directly, so position updates don't redraw everything.
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Duration get position => _player.position;
  bool get shuffle => queue.shuffle;
  RepeatSetting get repeat => queue.repeat;

  /// Starts playing [tracks] from [start].
  Future<void> playTracks(List<Track> tracks, {int start = 0, bool? shuffle, String? label}) async {
    if (tracks.isEmpty) return;
    // Choosing music while a book plays leaves book mode (the book's place is saved).
    _leaveBook();
    queue.setTracks(tracks, start: start, shuffle: shuffle, label: label);
    await _openCurrent();
  }

  /// Opens the queue's current song in the engine (with the next one loaded ahead) and plays it.
  /// Songs that can't be played are skipped. [startAt] starts part-way in (used for books).
  /// [skipped]: the songs passed over on the way here, so the note about them stays up while the
  /// song after them plays (before 0.1.81 it was cleared as that song opened, so it never showed).
  Future<void> _openCurrent({int? skipsLeft, Duration? startAt, List<Track> skipped = const []}) async {
    // Skip at most once round the whole queue (all songs unavailable).
    skipsLeft ??= queue.tracks.length - 1;
    final t = queue.current;
    // Opening a song means the listener wants it to play.
    pausedOnPurpose = false;
    // Nothing left to play: stop the engine and empty it.
    if (t == null) {
      pausedOnPurpose = true;
      await _player.stop();
      _engineIds = [];
      notifyListeners();
      return;
    }
    final uri = library.playableUri(t);
    if (uri == null) {
      // A song whose file isn't on this device (any more), or a server song
      // while the server is switched off: skip it. Its details are kept.
      final passed = [...skipped, t];
      lastError = _skipNote = _skippedNote(passed);
      if (skipsLeft > 0 && queue.next() != null) {
        return _openCurrent(skipsLeft: skipsLeft - 1, skipped: passed);
      }
      // Nothing playable left. HomeTunes: stop the engine too; before 0.1.15 the previous song
      // kept playing while the screen showed the unplayable one.
      pausedOnPurpose = true;
      _engineIds = [];
      try {
        await _player.stop();
      } catch (e) {
        debugPrint('HomeTunes: couldn\'t stop the engine: $e');
      }
      notifyListeners();
      return;
    }
    // Any note about songs skipped on the way here stays; otherwise a new song starts clean.
    lastError = _skipNote = skipped.isEmpty ? null : _skippedNote(skipped);
    PlaybackLog.add('Opening "${t.title}"${startAt != null && startAt > Duration.zero ? ' at ${startAt.inSeconds} s' : ''}');
    // Show the tagged length straight away; the engine's real length arrives a moment later.
    duration = t.duration;
    notifyListeners();
    // While this is above 0 the engine's events are ignored, as opening a file fires some
    // misleading ones (see the `completed` listener). try/finally makes sure it comes back down.
    _opening++;
    try {
      // A start of zero is left out, so the engine opens the file normally.
      final start = startAt != null && startAt > Duration.zero ? startAt : null;
      // Load the song after this one too, so it follows without a gap.
      await _syncLoopOne();
      final ahead = _songToLoadAhead();
      _engineIds = [t.id, if (ahead != null) ahead.$1.id];
      // Replace the engine's whole list with [this song, next song] and start at the first.
      await _player.openList([EngineMedia(uri, start: start), if (ahead != null) EngineMedia(ahead.$2)], play: true);
      // Make sure the new song actually starts, even if playback was paused
      // (e.g. pressing Next while paused, or after the previous song ended).
      if (!_player.isPlaying) await _player.play();
    } finally {
      _opening--;
    }
  }

  /// What [lastError] says about songs that couldn't be played and were passed over: the first
  /// one's name, and how many more.
  static String _skippedNote(List<Track> passed) {
    final t = passed.first;
    final more = passed.length > 1 ? ' (and ${passed.length - 1} more)' : '';
    return t.isLocal
        ? '"${t.title}"$more ${passed.length > 1 ? 'aren\'t' : 'isn\'t'} on this device – skipped'
        : 'Can\'t play "${t.title}"$more right now';
  }

  /// The skipped-songs note while it's showing, so the next song along can take it down.
  String? _skipNote;

  /// The song to load ahead in the engine (and its file / stream), if any.
  (Track, String)? _songToLoadAhead() {
    // Repeat-one uses the engine's own "loop this file" instead (loading the
    // same song ahead of itself stalls the engine – see player_gapless_test).
    if (!library.settings.playback.gaplessPlayback || queue.repeat == RepeatSetting.one) return null;
    // Null when the queue ends here, or when shuffle + repeat-all will reshuffle at the end.
    final next = queue.peekNextAuto();
    if (next == null) return null;
    final uri = library.playableUri(next);
    return uri == null ? null : (next, uri);
  }

  /// The engine went on to the song loaded ahead: catch the queue up, drop
  /// the finished song from the engine and load the one after.
  Future<void> _onEngineAdvanced() async {
    // Set before anything else, so a repeated "moved on" event from the
    // engine can't advance the queue twice.
    _engineEdits++;
    Track? next;
    try {
      // Move our queue forward and check it agrees with the song the engine went to.
      final expected = _engineIds[1];
      next = queue.next(auto: true);
      if (next == null || next.id != expected) {
        next = null; // out of step (shouldn't happen): reopened below
      } else {
        duration = next.duration;
        // The note about songs skipped before the previous one has had its song.
        if (_skipNote != null && lastError == _skipNote) lastError = null;
        _skipNote = null;
        // Drop the finished song from the engine, so the new one is at the front of its list.
        try {
          await _player.remove(0);
          _engineIds.removeAt(0);
        } catch (_) {
          // The engine's list changed underneath us; the sync below repairs it.
        }
        // In a book, save that we've reached the start of the next file.
        if (book != null) await listening?.record(book!, next.id, Duration.zero);
      }
    } finally {
      _engineEdits--;
    }
    // Out of step: reopen from our queue, which is always the one in charge.
    if (next == null) {
      await _openCurrent();
      return;
    }
    // The engine briefly counts itself as stopped at the end of each song;
    // make sure it carries on.
    if (!_player.isPlaying) await _player.play();
    notifyListeners();
    await _syncLoadedAhead();
  }

  /// After the queue changes (Play next, reorder, shuffle, repeat…), make
  /// sure the song loaded ahead in the engine is still the right one.
  Future<void> _syncLoadedAhead() async {
    await _syncLoopOne();
    // Leave it alone while a song is opening (_openCurrent loads the next one itself).
    if (_opening > 0 || _engineIds.isEmpty || queue.current == null) return;
    if (_engineIds.first != queue.current!.id) return; // a new song is being opened
    final want = _songToLoadAhead();
    final have = _engineIds.length > 1 ? _engineIds[1] : null;
    // Already right: nothing to do.
    if (want?.$1.id == have) return;
    // Swap the preloaded song: remove everything after the current one, then add the right one.
    // _engineEdits makes our own listeners ignore the engine events these edits cause.
    _engineEdits++;
    try {
      while (_engineIds.length > 1) {
        await _player.remove(_engineIds.length - 1);
        _engineIds.removeLast();
      }
      if (want != null) {
        await _player.add(EngineMedia(want.$2));
        _engineIds.add(want.$1.id);
      }
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t update the song loaded ahead: $e');
    } finally {
      _engineEdits--;
    }
  }

  /// Repeat-one: the engine loops the song by itself, with no gap.
  Future<void> _syncLoopOne() async {
    // Books never loop. Only talk to the engine when the setting actually changes.
    final loop = queue.repeat == RepeatSetting.one && book == null;
    if (_appliedLoopOne == loop) return;
    _appliedLoopOne = loop;
    try {
      await _player.setLoopOne(loop);
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t set repeat-one looping: $e');
    }
  }

  /// Sends the gapless and ReplayGain settings to the audio engine.
  Future<void> _applyEngineSettings() async {
    // These are mpv settings, so they only exist on the native (libmpv) engine.
    if (!_player.hasOptions) return;
    try {
      // 0.1.40: the engine is now the video build (for music videos), but this player only ever
      // plays sound. vid=no stops it decoding the pictures in an .mp4 song for nothing; the
      // music video is drawn by a separate, muted player (ui/widgets/music_video_view.dart).
      if (!_videoOff) {
        _videoOff = true;
        await _player.setOption('vid', 'no');
      }
      if (_appliedGapless != library.settings.playback.gaplessPlayback) {
        _appliedGapless = library.settings.playback.gaplessPlayback;
        // "yes": no gap even between files of different formats; the next
        // file is opened early so streams from a server are ready in time.
        await _player.setOption('gapless-audio', library.settings.playback.gaplessPlayback ? 'yes' : 'no');
        await _player.setOption('prefetch-playlist', library.settings.playback.gaplessPlayback ? 'yes' : 'no');
        await _syncLoadedAhead();
      }
      final rg = library.settings.playback.replayGain.name; // off / track / album
      if (_appliedReplayGain != rg) {
        _appliedReplayGain = rg;
        await _player.setOption('replaygain', rg == 'off' ? 'no' : rg);
      }
      // Volume boost (0.1.61 / 0.1.62): let the engine's volume go above 100 (it stops at 130
      // unless told); when the boost's top is lowered (or it's turned off), bring a louder
      // volume down to it.
      if (!_volumeMaxRaised) {
        _volumeMaxRaised = true;
        await _player.setOption('volume-max', '$engineVolumeMax');
      }
      if (volume > library.settings.playback.maxVolume) await setVolume(library.settings.playback.maxVolume);
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t apply playback settings: $e');
    }
  }

  /// Moves to the next song. [auto] is true when the song ended by itself, false when the
  /// user pressed Next. Also handles the end of the queue and the end of a book.
  Future<void> _advance({required bool auto}) async {
    final prev = queue.current;
    final next = queue.next(auto: auto);
    if (next == null) {
      if (book != null && auto && prev != null) {
        // The end of the book.
        await listening?.record(book!, prev.id, prev.duration, finished: true);
        pausedOnPurpose = true;
        PlaybackLog.add('End of the book');
        await _player.pause();
        notifyListeners();
        return;
      }
      // End of queue: stop at the start of the last song, like most players.
      pausedOnPurpose = true;
      PlaybackLog.add('End of the queue');
      await _player.pause();
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    if (book != null) {
      // Moving on to the next file of the book: remember that.
      await listening?.record(book!, next.id, Duration.zero);
    }
    // Repeat-one with the song ending by itself: just rewind and play, no need to reopen.
    if (auto && identical(next, prev) && queue.repeat == RepeatSetting.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    await _openCurrent();
  }

  /// The play/pause button.
  Future<void> togglePlay() async {
    if (queue.current == null) return;
    pausedOnPurpose = _player.isPlaying;
    await _player.playOrPause();
  }

  /// Resume (used by lock-screen / headset / media-key controls).
  Future<void> play() async {
    if (queue.current == null) return;
    pausedOnPurpose = false;
    await _player.play();
  }

  @override
  Future<void> pause() {
    pausedOnPurpose = true;
    return _player.pause();
  }

  // ---- the buttons ----
  // (Keeping "playing" honest is in player_model/stall_check.dart; the queue buttons and menus in
  // player_model/queue_actions.dart, refactor phase 11.)

  /// A swipe on the player (touch screens): left = next song, or skip forward in a book;
  /// right = previous song, or skip back in a book (by the Settings > Audiobooks lengths).
  Future<void> swipe({required bool forward}) {
    if (inBook) return forward ? skipForward() : skipBack();
    return forward ? next() : previous(restartFirst: false);
  }

  /// The Next button (also media keys and headset buttons).
  Future<void> next() => _advance(auto: false);

  /// Restarts the song if we're more than 3 seconds in, otherwise goes back.
  /// With [restartFirst] false (swiping), always goes to the previous song.
  Future<void> previous({bool restartFirst = true}) async {
    if (restartFirst && position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    queue.previous();
    await _openCurrent();
  }

  /// Moves to [d] in the current song or file.
  Future<void> seek(Duration d) async {
    await _player.seek(d);
    notifyListeners(); // lets the system media controls pick up the new position
  }
  @override
  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, library.settings.playback.maxVolume);
    notifyListeners();
    await _sendVolume();
  }

  /// The engine's volume: the listener's (0–100, or up to the volume boost's top, 0.1.62),
  /// turned down a little by the equaliser's overall level. Above 100 it's amplified
  /// (models/volume_boost.dart).
  double get _engineVolume => engineVolume(volume) * _eq.levelFactor;

  Future<void> _sendVolume() async {
    try {
      await _player.setVolume(_engineVolume);
    } catch (e) {
      debugPrint('HomeTunes: couldn\'t set the volume: $e');
    }
  }

  /// The volume before [toggleMute] silenced it, so unmuting puts it back.
  double? _volumeBeforeMute;

  /// Whether the volume is at 0.
  bool get muted => volume <= 0;

  /// Clicking the speaker icon beside any volume slider (0.1.27): mutes, or puts the volume
  /// back to where it was. If it was dragged to 0 by hand, unmuting goes to half volume.
  Future<void> toggleMute() {
    final (next, remembered) = muteToggle(volume, _volumeBeforeMute);
    _volumeBeforeMute = remembered;
    return setVolume(next);
  }

  /// The new volume and what to remember, for a mute / unmute from [volume] (0 to 100).
  static (double, double?) muteToggle(double volume, double? remembered) {
    if (volume > 0) return (0, volume);
    return ((remembered ?? 0) > 0 ? remembered! : 50, null);
  }

  /// Sends the equaliser preset for what's playing (music or a book) to the
  /// engine. Only talks to the engine when something actually changed.
  /// (A slider being dragged sends many changes a second; the chain takes one at a time and
  /// then catches up with the latest. A refused filter is shown on the Equaliser screen.)
  Future<void> _applyEqualizer() => _eq.update();

  // ---- audiobooks ----
  // (Playing a book, the waiting music, skipping, chapters and speed are in player_model/books.dart,
  // refactor phase 11; what the sleep timer reads stays here.)

  /// True while an audiobook (rather than music) is playing.
  @override
  bool get inBook => book != null;

  /// A music queue is waiting to be picked up again (see [resumeMusic]).
  bool get hasWaitingMusic => _music != null && _music!.tracks.isNotEmpty;

  /// How far to go back when resuming, so the sentence isn't cut off:
  /// more the longer it's been.
  static Duration resumeRewind(Duration sinceLastListen) {
    if (sinceLastListen < const Duration(minutes: 1)) return const Duration(seconds: 2);
    if (sinceLastListen < const Duration(hours: 1)) return const Duration(seconds: 10);
    return const Duration(seconds: 30);
  }

  /// Saves the place in the playing book (every 10 s, on pause, when the app
  /// goes to the background, and before switching away).
  @override
  void saveBookPlace() {
    final b = book;
    final t = queue.current;
    // Not while a file is opening: the engine's position would still belong to the old file.
    if (b == null || t == null || _opening > 0) return;
    listening?.record(b, t.id, _player.position);
  }

  /// Time from the start of the playing book to where we are.
  @override
  Duration get bookOffset {
    final b = book;
    if (b == null) return position;
    return b.offsetOf(queue.position, position);
  }

  /// The chapter we're in (-1 for music).
  @override
  int get currentChapterIndex => book == null ? -1 : chapterIndexAt(_chapters, bookOffset);

  /// Index of the chapter that [offset] (from the start of the book) is in.
  static int chapterIndexAt(List<BookChapter> chapters, Duration offset) {
    // Chapters are in order, so walk forward until one starts after [offset]. Before the first
    // chapter starts counts as the first chapter.
    if (chapters.isEmpty) return -1;
    var found = 0;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].offset <= offset) {
        found = i;
      } else {
        break;
      }
    }
    return found;
  }

  /// Where chapter [i] ends, from the start of the book.
  @override
  Duration chapterEnd(int i) {
    final b = book;
    if (b == null || i < 0) return Duration.zero;
    return i + 1 < _chapters.length ? _chapters[i + 1].offset : b.duration;
  }

  /// Where a skip of [delta] from [position] in file [part] lands, given the
  /// lengths of the files (one file for a song). Crosses into the previous /
  /// next file of a book. Returns null when a song would skip past its end.
  static (int, Duration)? skipTarget(List<Duration> lengths, int part, Duration position, Duration delta) {
    var target = position + delta;
    // Going back past the start of a file: step into the previous file(s).
    while (target.isNegative && part > 0) {
      part--;
      target += lengths[part];
    }
    // Before the start of the first file: stop at the very start.
    if (target.isNegative) target = Duration.zero;
    // Going forward past the end of a file: step into the next file(s). A file whose length
    // isn't known (zero) stops the walk, since we can't tell where it ends.
    while (part < lengths.length - 1 && lengths[part] > Duration.zero && target >= lengths[part]) {
      target -= lengths[part];
      part++;
    }
    // Still past the end of the last file.
    final length = lengths[part];
    if (length > Duration.zero && target >= length) {
      if (lengths.length == 1) return null;
      target = length - const Duration(seconds: 1); // the very end of the book
    }
    return (part, target);
  }

  /// The speeds offered in the speed menu.
  static const speeds = [0.75, 0.9, 1.0, 1.1, 1.2, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5];


  /// Tells the watchers something changed. For the methods in player_model/*.dart (extensions
  /// can't call notifyListeners, which only the class itself may use).
  void _changed() => notifyListeners();

  @override
  void dispose() {
    // Save the book place one last time before shutting the engine down.
    _saveTimer?.cancel();
    _learnTimer?.cancel();
    _watchdog?.cancel();
    saveBookPlace();
    library.removeListener(_onLibraryChanged);
    library.settings.playback.removeListener(_applyEngineSettings);
    equalizer?.removeListener(_applyEqualizer);
    _eq.close();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
