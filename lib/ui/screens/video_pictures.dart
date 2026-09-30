// Videos (0.1.32): choosing a video's picture ("Change picture…") or a collection's poster
// ("Change poster…"), instead of the frame taken automatically a tenth of the way in:
//   - Choose an image file…     any picture on this computer / phone;
//   - Pick a frame…             a small player to scrub through the video (frame by frame too);
//   - Search online…            TVmaze, AniList and Wikipedia (services/video_art_search.dart),
//                               when Settings › Online lookups allows it;
//   - Use the automatic picture (only once one has been chosen).
// Chosen pictures are shrunk to at most 1280 px wide and kept in art/video/custom/
// (VideoLibraryModel.setPicture / setPoster). The player page also has "Use this frame".
import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../services/video_art_search.dart';
import '../../services/video_thumbnails.dart' show shrinkToJpeg;
import '../../state/library_model.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';

/// Chosen pictures are kept at most this wide.
const pictureWidth = 1280;

/// Makes a picture a sensible size (never bigger). Throws if it isn't a picture.
Future<List<int>> preparePicture(List<int> bytes) async {
  final small = await shrinkToJpeg(bytes, width: pictureWidth, quality: 88, onlyShrink: true);
  if (small == null) throw const FormatException('That isn\'t a picture HomeTunes can read');
  return small;
}

/// What to add to a Wikipedia search for this category, and whether to ask AniList first.
({String? hint, bool anime}) _searchHints(String? category) {
  final c = (category ?? '').toLowerCase();
  if (c.contains('anime')) return (hint: 'anime', anime: true);
  if (c.contains('film') || c.contains('movie')) return (hint: 'film', anime: false);
  if (c == 'tv' || c.contains('series') || c.contains('show')) return (hint: 'TV series', anime: false);
  return (hint: null, anime: false);
}

/// Change picture… for one video.
Future<void> showVideoPictureOptions(BuildContext context, VideoItem v) async {
  final model = context.read<VideoLibraryModel>();
  final online = context.read<LibraryModel>().onlineVideoArt;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final choice = await _askHow(context,
      title: 'Picture for "${v.title}"',
      frameLabel: 'Pick a frame from the video…',
      online: online,
      canReset: model.hasOwnPicture(v));
  if (choice == null || !context.mounted) return;
  if (choice == 'auto') {
    await model.setPicture(v, null);
    messenger?.showSnackBar(const SnackBar(content: Text('Back to the automatic picture')));
    return;
  }
  final hints = _searchHints(v.category);
  final bytes = await _getPicture(context, choice,
      frameOf: v,
      query: v.collection,
      season: v.season,
      episode: v.episode,
      hints: hints,
      forPoster: false);
  if (bytes == null) return;
  await model.setPicture(v, bytes);
  messenger?.showSnackBar(SnackBar(content: Text('New picture for "${v.title}"')));
}

/// Change poster… for a collection.
Future<void> showCollectionPosterOptions(BuildContext context, VideoCollection c) async {
  final model = context.read<VideoLibraryModel>();
  final online = context.read<LibraryModel>().onlineVideoArt;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final frameOf = model.nextUp(c) ?? (c.main.isNotEmpty ? c.main.first : (c.videos.isNotEmpty ? c.videos.first : null));
  final choice = await _askHow(context,
      title: 'Poster for "${c.name}"',
      frameLabel: frameOf == null ? null : 'Pick a frame from ${frameOf.episodeLabel ?? '"${frameOf.title}"'}…',
      online: online,
      canReset: model.hasOwnPoster(c));
  if (choice == null || !context.mounted) return;
  if (choice == 'auto') {
    await model.setPoster(c, null);
    messenger?.showSnackBar(const SnackBar(content: Text('Back to the automatic poster')));
    return;
  }
  final bytes = await _getPicture(context, choice,
      frameOf: frameOf, query: c.name, hints: _searchHints(c.category), forPoster: true);
  if (bytes == null) return;
  // The collection may have been renamed meanwhile: find it again by one of its videos.
  final now = frameOf != null ? (model.collectionOf(model.byId(frameOf.id) ?? frameOf) ?? c) : c;
  await model.setPoster(now, bytes);
  messenger?.showSnackBar(SnackBar(content: Text('New poster for "${now.name}"')));
}

Future<String?> _askHow(BuildContext context,
    {required String title, required String? frameLabel, required bool online, required bool canReset}) {
  Widget option(BuildContext ctx, String value, IconData icon, String label, String detail, {bool enabled = true}) =>
      SimpleDialogOption(
        key: ValueKey('picture-$value'),
        onPressed: enabled ? () => Navigator.of(ctx).pop(value) : null,
        child: ListTile(
          enabled: enabled,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(detail, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      );
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        option(ctx, 'file', Icons.image_outlined, 'Choose an image file…', 'A picture you already have'),
        if (frameLabel != null)
          option(ctx, 'frame', Icons.movie_filter_outlined, frameLabel, 'Scrub to the moment you want, frame by frame if you like'),
        option(ctx, 'online', Icons.travel_explore, 'Search online…',
            online ? 'Posters and stills from TVmaze, AniList and Wikipedia' : 'Switched off in Settings › Online lookups',
            enabled: online),
        if (canReset) option(ctx, 'auto', Icons.restore, 'Use the automatic picture', 'Go back to what HomeTunes chose'),
      ],
    ),
  );
}

/// Gets the picture the chosen way; null if cancelled. Problems are shown, not thrown.
Future<List<int>?> _getPicture(
  BuildContext context,
  String how, {
  required VideoItem? frameOf,
  required String query,
  int? season,
  int? episode,
  required ({String? hint, bool anime}) hints,
  required bool forPoster,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    switch (how) {
      case 'file':
        final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture');
        final path = file?.path;
        if (path == null) return null;
        return await preparePicture(await File(path).readAsBytes());
      case 'frame':
        if (frameOf == null) return null;
        return await showFramePicker(context, frameOf);
      case 'online':
        return await showPictureSearch(context,
            query: query, season: season, episode: episode, hint: hints.hint, anime: hints.anime, forPoster: forPoster);
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: ${e is FormatException ? e.message : e}')));
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Pick a frame
// ---------------------------------------------------------------------------------------------

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
  final Player _player = Player(configuration: const PlayerConfiguration(title: 'HomeTunes frame picker'));
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
      final engine = _player.platform;
      if (engine is NativePlayer) {
        await engine.setProperty('vid', 'auto'); // media_kit starts players with pictures off
        await engine.setProperty('aid', 'no'); // silent
        await engine.setProperty('sid', 'no');
        await engine.setProperty('hr-seek', 'yes'); // land on the exact frame
      }
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
    final engine = _player.platform;
    if (engine is NativePlayer) await engine.command([forward ? 'frame-step' : 'frame-back-step']);
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

/// Searches TVmaze, AniList and Wikipedia for [query] and lets the user pick a picture, which is
/// downloaded and returned (null if cancelled). [search] can be replaced by tests.
Future<List<int>?> showPictureSearch(
  BuildContext context, {
  required String query,
  int? season,
  int? episode,
  String? hint,
  bool anime = false,
  bool forPoster = false,
  VideoArtSearch? search,
}) =>
    showDialog<List<int>>(
      context: context,
      builder: (_) => _PictureSearch(
          query: query, season: season, episode: episode, hint: hint, anime: anime, forPoster: forPoster, search: search),
    );

class _PictureSearch extends StatefulWidget {
  final String query;
  final int? season, episode;
  final String? hint;
  final bool anime, forPoster;
  final VideoArtSearch? search;
  const _PictureSearch(
      {required this.query, this.season, this.episode, this.hint, required this.anime, required this.forPoster, this.search});

  @override
  State<_PictureSearch> createState() => _PictureSearchState();
}

class _PictureSearchState extends State<_PictureSearch> {
  late final VideoArtSearch _search = widget.search ?? VideoArtSearch();
  late final _query = TextEditingController(text: widget.query);
  VideoArtResults? _results;
  bool _busy = false;
  String? _downloading;
  String? _problem;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void dispose() {
    _query.dispose();
    if (widget.search == null) _search.close();
    super.dispose();
  }

  Future<void> _find() async {
    final run = ++_run;
    setState(() {
      _busy = true;
      _problem = null;
    });
    // The typed name may no longer be the show's: only ask for the episode's still when unchanged.
    final same = _query.text.trim() == widget.query.trim();
    final r = await _search.search(_query.text,
        season: same ? widget.season : null,
        episode: same ? widget.episode : null,
        wikipediaHint: widget.hint,
        order: widget.anime ? const ['AniList', 'TVmaze', 'Wikipedia'] : VideoArtSearch.services);
    if (!mounted || run != _run) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  Future<void> _pick(VideoArtCandidate c) async {
    setState(() {
      _downloading = c.fullUrl;
      _problem = null;
    });
    try {
      final bytes = await _search.download(c);
      final picture = await preparePicture(bytes);
      if (mounted) Navigator.of(context).pop(picture);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = null;
          _problem = 'Couldn\'t get that picture: ${e is FormatException ? e.message : e}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    // Posters first when choosing a collection's poster, wide pictures first for a video.
    final found = r == null
        ? const <VideoArtCandidate>[]
        : [...r.found.where((c) => c.tall == widget.forPoster), ...r.found.where((c) => c.tall != widget.forPoster)];
    return AlertDialog(
      title: const Text('Search online'),
      content: SizedBox(
        width: 780,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('picture-search-box'),
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _find(),
                decoration: const InputDecoration(labelText: 'Name to search for'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _busy ? null : _find),
          ]),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          if (r != null && r.failed.isNotEmpty)
            Text('Couldn\'t reach ${r.failed.join(' or ')} just now.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          if (_problem != null) Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          const SizedBox(height: 4),
          Expanded(
            child: !_busy && r != null && found.isEmpty
                ? Center(child: Text('Nothing found. Try another name.', style: TextStyle(color: AppColors.textDim)))
                : GridView.extent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.66,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final c in found)
                        _ResultTile(
                          candidate: c,
                          busy: _downloading == c.fullUrl,
                          onTap: _downloading == null ? () => _pick(c) : null,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pictures from TVmaze (CC BY-SA), AniList and Wikipedia. Film posters on Wikipedia are usually '
            'copyrighted: fine for your own library, not for sharing.',
            style: TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final VideoArtCandidate candidate;
  final bool busy;
  final VoidCallback? onTap;
  const _ResultTile({required this.candidate, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    return Tooltip(
      message: '${c.title}\n${c.kind} from ${c.source}',
      child: InkWell(
        borderRadius: AppShape.circular(8),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: AppShape.circular(8),
              child: Container(
                color: AppColors.surface,
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(
                    c.previewUrl,
                    fit: BoxFit.contain,
                    cacheWidth: 380,
                    headers: const {'User-Agent': VideoArtSearch.userAgent},
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (_, _, _) => Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textDim)),
                  ),
                  if (busy)
                    const ColoredBox(color: Colors.black45, child: Center(child: CircularProgressIndicator())),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${c.kind} · ${c.source}', maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Picture shape (Edit details / Edit collection)
// ---------------------------------------------------------------------------------------------

/// Chooses a picture shape: "Usual" (null: whatever Settings › Videos says, [usual]), Wide,
/// Tall or Square. With [mixed] (several videos that differ) nothing is picked until the user
/// picks, and [onChanged] is only called then.
class PictureShapePicker extends StatelessWidget {
  final String title;
  final PictureShape? value;
  final PictureShape usual;
  final bool mixed;
  final ValueChanged<PictureShape?> onChanged;
  const PictureShapePicker(
      {super.key, required this.title, required this.value, required this.usual, required this.onChanged, this.mixed = false});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<PictureShape?>(
          key: const ValueKey('picture-shape'),
          emptySelectionAllowed: mixed,
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: null, label: Text('Usual (${usual.label.toLowerCase()})')),
            // Words only, so all four fit across an editor.
            for (final s in PictureShape.values) ButtonSegment(value: s, label: Text(s.label), tooltip: s.label),
          ],
          selected: mixed ? const {} : {value},
          onSelectionChanged: (v) {
            if (v.isNotEmpty) onChanged(v.first);
          },
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------
// How collection posters are drawn
// ---------------------------------------------------------------------------------------------

/// A collection's picture in a wide box: the whole picture, over a blurred, stretched copy of
/// itself (so a tall poster isn't cut down to its middle, and a wide one simply fills the box).
class PosterPicture extends StatelessWidget {
  final String? file;
  final IconData icon;
  const PosterPicture({super.key, required this.file, this.icon = Icons.video_library_outlined});

  @override
  Widget build(BuildContext context) {
    final f = file;
    final none = Center(child: Icon(icon, size: 40, color: AppColors.textDim));
    if (f == null) return Container(color: AppColors.surface, child: none);
    final image = FileImage(File(f));
    final provider = ResizeImage(image, width: 640, policy: ResizeImagePolicy.fit);
    return Container(
      color: AppColors.surface,
      child: Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Image(image: provider, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
        const ColoredBox(color: Color(0x33000000)),
        Image(image: provider, fit: BoxFit.contain, errorBuilder: (_, _, _) => none),
      ]),
    );
  }
}
