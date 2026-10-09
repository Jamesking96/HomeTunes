// Pick a frame: a silent player of the video with a slider and frame-by-frame steps, for a video's
// picture or a collection's poster. Split out of video_pictures.dart in refactor phase 6
// (9 Oct 2026), unchanged.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../../../models/video_item.dart';
import '../../../services/engine/engines.dart';
import '../../../state/video_library_model.dart';
import '../video_pictures.dart';

/// A small silent player to find the frame to use. Returns the picture, or null.
Future<List<int>?> showFramePicker(BuildContext context, VideoItem v) {
  final file = context.read<VideoLibraryModel>().playableFile(v);
  if (file == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('The video file can\'t be found')));
    return Future.value(null);
  }
  return showDialog<List<int>>(context: context, builder: (_) => _FramePicker(video: v, path: file));
}

class _FramePicker extends StatefulWidget {
  final VideoItem video;
  final String path;
  const _FramePicker({required this.video, required this.path});

  @override
  State<_FramePicker> createState() => _FramePickerState();
}

class _FramePickerState extends State<_FramePicker> {
  final Player _player = createEngine(EngineUse.framePicker);
  late final VideoController _controller = VideoController(_player);
  final List<StreamSubscription> _subs = [];
  Duration _length = Duration.zero;
  Duration _at = Duration.zero;
  bool _dragging = false;
  bool _ready = false;
  bool _taking = false;
  String? _problem;
  Timer? _seek;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      // Pictures on, silent, no subtitles, and seeks land on the exact frame.
      await prepareEngine(_player, EngineUse.framePicker);
      await _player.setVolume(0);
      _subs.add(_player.stream.position.listen((pos) {
        if (!_dragging && mounted) setState(() => _at = pos);
      }));
      await _player.open(Media(widget.path), play: false);
      // Wait (up to 10 s) until the engine knows the length.
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (_player.state.duration <= Duration.zero) {
        if (DateTime.now().isAfter(end)) throw TimeoutException('No length');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final length = _player.state.duration;
      // Start where the automatic picture was taken: a tenth of the way in, at most a minute.
      var start = length * 0.1;
      if (start > const Duration(minutes: 1)) start = const Duration(minutes: 1);
      await _player.seek(start);
      if (mounted) {
        setState(() {
          _length = length;
          _at = start;
          _ready = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _problem = 'This video can\'t be opened here');
    }
  }

  void _seekTo(Duration d) {
    if (d < Duration.zero) d = Duration.zero;
    if (d > _length) d = _length;
    setState(() => _at = d);
    // While dragging, seek at most every 120 ms so the engine keeps up.
    _seek?.cancel();
    _seek = Timer(const Duration(milliseconds: 120), () => _player.seek(_at));
  }

  Future<void> _step(bool forward) async {
    await Mpv.of(_player)?.command([forward ? 'frame-step' : 'frame-back-step']);
  }

  Future<void> _use() async {
    setState(() => _taking = true);
    try {
      List<int>? shot;
      for (var i = 0; i < 20 && shot == null; i++) {
        shot = await _player.screenshot(format: 'image/jpeg');
        if (shot == null) await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (shot == null) throw const FormatException('No picture came from the video');
      final picture = await preparePicture(shot);
      if (mounted) Navigator.of(context).pop(picture);
    } catch (e) {
      if (mounted) {
        setState(() {
          _taking = false;
          _problem = 'Couldn\'t take that frame: ${e is FormatException ? e.message : e}';
        });
      }
    }
  }

  @override
  void dispose() {
    _seek?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  static String _time(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000) ~/ 100;
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}.$ms'
        : '${d.inMinutes}:${two(d.inSeconds % 60)}.$ms';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final ratio = (v.width != null && v.height != null && v.height! > 0) ? v.width! / v.height! : 16 / 9;
    final max = _length.inMilliseconds.toDouble();
    return AlertDialog(
      title: Text('Pick a frame · ${v.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 720,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: ratio,
            child: Container(
              color: Colors.black,
              child: _problem != null && !_ready
                  ? Center(child: Text(_problem!, style: const TextStyle(color: Colors.white70)))
                  : Video(
                      controller: _controller,
                      controls: NoVideoControls,
                      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            key: const ValueKey('frame-slider'),
            value: max <= 0 ? 0 : _at.inMilliseconds.clamp(0, _length.inMilliseconds).toDouble(),
            max: max <= 0 ? 1 : max,
            onChangeStart: _ready ? (_) => _dragging = true : null,
            onChanged: _ready ? (x) => _seekTo(Duration(milliseconds: x.round())) : null,
            onChangeEnd: _ready
                ? (x) {
                    _dragging = false;
                    _seek?.cancel();
                    _player.seek(Duration(milliseconds: x.round()));
                  }
                : null,
          ),
          Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
            IconButton(
                tooltip: 'Back 10 seconds',
                icon: const Icon(Icons.replay_10),
                onPressed: _ready ? () => _seekTo(_at - const Duration(seconds: 10)) : null),
            IconButton(
                tooltip: 'Back one frame', icon: const Icon(Icons.skip_previous), onPressed: _ready ? () => _step(false) : null),
            SizedBox(
              width: 150,
              child: Text('${_time(_at)} / ${_time(_length)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
            ),
            IconButton(
                tooltip: 'Forward one frame', icon: const Icon(Icons.skip_next), onPressed: _ready ? () => _step(true) : null),
            IconButton(
                tooltip: 'Forward 10 seconds',
                icon: const Icon(Icons.forward_10),
                onPressed: _ready ? () => _seekTo(_at + const Duration(seconds: 10)) : null),
          ]),
          if (_problem != null && _ready)
            Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(
          icon: _taking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Use this frame'),
          onPressed: _ready && !_taking ? _use : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Search online
// ---------------------------------------------------------------------------------------------
