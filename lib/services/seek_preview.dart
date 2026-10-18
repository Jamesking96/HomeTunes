// Seek preview (0.1.84): the small picture above a video's progress bar that shows where the
// video would land, while the mouse is over the bar or while it's being dragged (the user, 18 Oct:
// "a small preview that will show when moving forward and backwards in a video").
//
// A second, hidden and silent player opens the same video the first time a preview is wanted,
// jumps to the nearest key frame before each spot (fast: no decoding up to the exact frame), has
// mpv write that frame as a JPEG (mpv's own encoder: ~45 ms for a 4K frame, where media_kit's
// screenshot took ~600 ms), and shrinks it to 320 px wide (~8 KB). Checked on the real engine with
// tool/bench/seek_preview_engine_test.dart. Only the newest spot asked for is fetched: while the
// mouse sweeps along the bar, spots it has already passed are dropped. Pictures are kept for spots
// close together, so going back over the bar shows them at once. The hidden player closes after a
// couple of idle minutes, and with the video page.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'engine/engines.dart';
import 'video_thumbnails.dart' show shrinkToJpeg;

/// One preview picture: the spot it was asked for, and the picture (JPEG).
@immutable
class SeekFrame {
  const SeekFrame(this.at, this.picture);
  final Duration at;
  final Uint8List picture;
}

/// Where the preview pictures come from: the hidden player in the app, a fake in tests.
abstract class SeekFrameSource {
  /// Opens [source] (a file or a server address). Throws if it can't be opened.
  Future<void> open(String source);

  /// The picture at (or just before) [at] in the open video, or null if none came.
  Future<Uint8List?> frameAt(Duration at);

  Future<void> close();
}

/// The width of the preview pictures.
const seekPreviewWidth = 320;

/// The hidden player (EngineUse.seekPreview).
class EngineSeekFrames implements SeekFrameSource {
  Player? _player;

  /// Where mpv writes each frame (one file per player, written over each time).
  static int _count = 0;
  final String _shotFile = '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'hometunes_seek_${DateTime.now().microsecondsSinceEpoch}_${_count++}.jpg';

  @override
  Future<void> open(String source) async {
    var player = _player;
    if (player == null) {
      player = _player = createEngine(EngineUse.seekPreview);
      await prepareEngine(player, EngineUse.seekPreview);
      await player.setVolume(0);
    }
    await player.open(Media(source), play: false);
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (player.state.duration <= Duration.zero || (player.state.width ?? 0) <= 0) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('The video didn\'t open');
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
  }

  @override
  Future<Uint8List?> frameAt(Duration at) async {
    final player = _player;
    if (player == null) return null;
    await player.seek(at);
    // Wait for the jump to land. media_kit reports the asked-for spot straight away while mpv is
    // still seeking (see tool/bench/frame_picker_engine_test.dart), so ask mpv itself: settled
    // means "not seeking" a few times running.
    final mpv = Mpv.of(player);
    if (mpv != null) {
      final end = DateTime.now().add(const Duration(milliseconds: 800));
      var settled = 0;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      while (settled < 3 && DateTime.now().isBefore(end)) {
        settled = await mpv.get('seeking') == 'no' ? settled + 1 : 0;
        if (settled < 3) await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    }
    // The first one right after a jump can fail: try a few times.
    List<int>? shot;
    for (var i = 0; i < 8 && (shot == null || shot.isEmpty); i++) {
      // After a few misses, media_kit's own (slower) screenshot, in case mpv can't write one here.
      shot = await _shoot(player, i < 4 ? mpv : null);
      if (shot == null || shot.isEmpty) await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (shot == null || shot.isEmpty) return null;
    final small = await shrinkToJpeg(shot, width: seekPreviewWidth, quality: 75, onlyShrink: true);
    return small == null ? null : Uint8List.fromList(small);
  }

  /// The frame on show, as a JPEG: written by mpv itself, or media_kit's screenshot without mpv.
  Future<List<int>?> _shoot(Player player, Mpv? mpv) async {
    try {
      if (mpv == null) return await player.screenshot(format: 'image/jpeg');
      await mpv.command(['screenshot-to-file', _shotFile, 'video']);
      final file = File(_shotFile);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    final player = _player;
    _player = null;
    await player?.dispose();
    try {
      await File(_shotFile).delete();
    } catch (_) {}
  }
}

/// Fetches preview pictures for one video page (and its full screen).
class SeekPreviewer {
  SeekPreviewer({SeekFrameSource? source, this.idleClose = const Duration(minutes: 2)})
      : _source = source ?? EngineSeekFrames();

  final SeekFrameSource _source;

  /// How long the hidden player stays open with nothing asked of it.
  final Duration idleClose;

  /// The newest picture fetched (null before the first, and after the video changes).
  final ValueNotifier<SeekFrame?> frame = ValueNotifier(null);

  /// The most pictures kept for one video.
  static const keep = 150;

  String? _file;
  String? _opened;
  bool _broken = false;
  (Duration, Duration)? _wanted;
  bool _busy = false;
  bool _disposed = false;
  Timer? _idle;
  final _pictures = <int, Uint8List>{}; // by [bucket], oldest first

  /// The video on the page now (its file or server address). A new one clears the pictures.
  void setVideo(String? file) {
    if (file == _file) return;
    _file = file;
    _broken = false;
    _pictures.clear();
    frame.value = null;
  }

  /// Spots in the same bucket share a picture: every 2 seconds, or a 400th of a long video
  /// ([length] long).
  static int bucket(Duration at, Duration length) {
    final step = length.inMilliseconds ~/ 400 > 2000 ? length.inMilliseconds ~/ 400 : 2000;
    return at.inMilliseconds ~/ step;
  }

  /// A kept picture for [at] in a video [length] long, straight away, or null.
  Uint8List? keptFor(Duration at, Duration length) => _pictures[bucket(at, length)];

  /// Asks for the picture at [at] in a video [length] long. Only the newest spot asked for is
  /// fetched; [frame] changes when it comes.
  void request(Duration at, Duration length) {
    if (_disposed || _file == null || _broken) return;
    final kept = keptFor(at, length);
    if (kept != null) {
      _wanted = null;
      frame.value = SeekFrame(at, kept);
      return;
    }
    _wanted = (at, length);
    if (!_busy) unawaited(_run());
  }

  Future<void> _run() async {
    _busy = true;
    _idle?.cancel();
    try {
      while (!_disposed && _wanted != null) {
        final (at, length) = _wanted!;
        _wanted = null;
        final file = _file;
        if (file == null) break;
        if (_opened != file) {
          try {
            await _source.open(file);
            _opened = file;
          } catch (_) {
            _broken = true; // no previews for this video, rather than trying again and again
            break;
          }
        }
        final picture = await _source.frameAt(at);
        if (_disposed || file != _file || picture == null) continue;
        final key = bucket(at, length);
        _pictures.remove(key);
        _pictures[key] = picture;
        while (_pictures.length > keep) {
          _pictures.remove(_pictures.keys.first);
        }
        frame.value = SeekFrame(at, picture);
      }
    } finally {
      _busy = false;
      if (!_disposed) _idle = Timer(idleClose, _closeIdle);
    }
  }

  void _closeIdle() {
    if (_busy || _disposed) return;
    _opened = null;
    unawaited(_source.close());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _idle?.cancel();
    frame.dispose();
    await _source.close();
  }
}
