// Videos (0.1.32): one video's player page, opened from the Videos tab.
//
// The video plays in its own player (media_kit's Video widget with its standard controls: seek
// bar, play/pause, volume, and a full-screen button; on a computer the keyboard works too:
// Space, the arrow keys, F for full screen and Esc to leave it). Under it are the details
// (collection, year, genre, length, picture size, format, description) and buttons for Enlarge
// (the video fills the whole page, details hidden), Full screen, Edit details and Mark as watched.
// It carries on from where it was left (and says so, with Start over), saves the place every few
// seconds and when the page closes, and counts as watched near the end. Starting a video pauses
// the music; starting music pauses the video.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/player_model.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';
import 'edit_video.dart';
import 'videos_screen.dart' show videoLength;

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  const VideoPlayerScreen({super.key, required this.videoId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final Player _player = Player(configuration: const PlayerConfiguration(title: 'HomeTunes video'));
  late final VideoController _controller = VideoController(_player);
  // Keeps the same Video widget (and its picture) when switching between normal and enlarged.
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  late final VideoLibraryModel _videos;
  late final PlayerModel _music;
  final List<StreamSubscription> _subs = [];
  Timer? _saveTimer;

  /// The video fills the whole page (the details are hidden).
  bool _enlarged = false;

  /// The file couldn't be found or opened.
  String? _problem;

  @override
  void initState() {
    super.initState();
    _videos = context.read<VideoLibraryModel>();
    _music = context.read<PlayerModel>();
    _music.addListener(_onMusicChanged);
    _open();
  }

  Future<void> _open() async {
    final v = _videos.byId(widget.videoId);
    final file = v == null ? null : _videos.playableFile(v);
    if (v == null || file == null) {
      setState(() => _problem = 'This video isn\'t there any more. Rescan your video folders to tidy the list.');
      return;
    }
    // One thing at a time: the music pauses while a video plays.
    if (_music.playing) await _music.pause();
    final start = resumeAt(_videos.placeOf(v.id), v.duration);
    _subs.addAll([
      _player.stream.completed.listen((done) {
        if (done) _savePlace(end: true);
      }),
      _player.stream.error.listen((e) {
        if (mounted && _player.state.duration == Duration.zero) setState(() => _problem = 'Can\'t play this video: $e');
      }),
      _player.stream.playing.listen((playing) {
        if (!playing) _savePlace();
      }),
    ]);
    await _player.open(Media(file, start: start > Duration.zero ? start : null));
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_player.state.playing) _savePlace();
    });
    if (start > Duration.zero && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Carrying on from ${videoLength(start)}'),
        action: SnackBarAction(label: 'Start over', onPressed: () => _player.seek(Duration.zero)),
      ));
    }
  }

  /// Music started while the video plays: pause the video.
  void _onMusicChanged() {
    if (_music.playing && _player.state.playing) _player.pause();
  }

  void _savePlace({bool end = false}) {
    final length = _player.state.duration;
    if (length <= Duration.zero) return;
    final at = end ? length : _player.state.position;
    if (at <= Duration.zero) return;
    _videos.savePlace(widget.videoId, at, length);
  }

  @override
  void dispose() {
    // Save the place once this frame is done (telling the Videos tab during dispose would redraw
    // it while the widget tree is locked).
    final length = _player.state.duration, at = _player.state.position;
    final id = widget.videoId, videos = _videos;
    if (length > Duration.zero && at > Duration.zero) Future.microtask(() => videos.savePlace(id, at, length));
    _saveTimer?.cancel();
    _music.removeListener(_onMusicChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _fullScreen() async => _videoKey.currentState?.enterFullscreen();

  @override
  Widget build(BuildContext context) {
    final v = context.select<VideoLibraryModel, VideoItem?>((m) => m.byId(widget.videoId));
    final watched = context.select<VideoLibraryModel, bool>((m) => m.placeOf(widget.videoId)?.watched ?? false);
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This video isn\'t in your library any more.')));
    }

    final video = _problem != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_problem!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            ),
          )
        : Video(key: _videoKey, controller: _controller, fill: Colors.black);

    // Enlarged: the video fills the page, with a small bar to shrink it again.
    if (_enlarged) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: video),
          Positioned(
            left: 8,
            top: 8,
            child: _OverlayButton(
              icon: Icons.fullscreen_exit,
              tooltip: 'Shrink',
              onPressed: () => setState(() => _enlarged = false),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: _OverlayButton(icon: Icons.fullscreen, tooltip: 'Full screen', onPressed: _fullScreen),
          ),
        ]),
      );
    }

    final facts = [
      v.collection,
      if (v.year != null) '${v.year}',
      if (v.genre != null) v.genre!,
      if (v.duration > Duration.zero) videoLength(v.duration),
      if (v.resolution != null) v.resolution!,
      v.format,
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit details',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showEditVideos(context, [v]),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        // As big as fits: the video's own shape, at most 70 % of the page's height.
        final ratio = (v.width != null && v.height != null && v.height! > 0) ? v.width! / v.height! : 16 / 9;
        var h = c.maxWidth / ratio;
        if (h > c.maxHeight * 0.7) h = c.maxHeight * 0.7;
        return ListView(children: [
          Container(color: Colors.black, height: h, child: video),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(facts, style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.open_in_full),
                  label: const Text('Enlarge'),
                  onPressed: () => setState(() => _enlarged = true),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Full screen'),
                  onPressed: _problem == null ? _fullScreen : null,
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit details'),
                  onPressed: () => showEditVideos(context, [v]),
                ),
                OutlinedButton.icon(
                  icon: Icon(watched ? Icons.remove_done : Icons.check_circle_outline),
                  label: Text(watched ? 'Mark as not watched' : 'Mark as watched'),
                  onPressed: () => _videos.setWatched([v.id], !watched),
                ),
                if (Platform.isWindows)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Show in folder'),
                    onPressed: () {
                      final file = _videos.playableFile(v);
                      if (file != null) Process.run('explorer', ['/select,', p.normalize(file)]);
                    },
                  ),
              ]),
              if (v.description != null) ...[
                const SizedBox(height: 16),
                SelectableText(v.description!),
              ],
              const SizedBox(height: 24),
            ]),
          ),
        ]);
      }),
    );
  }
}

/// A round, see-through button over a video.
class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _OverlayButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      );
}
