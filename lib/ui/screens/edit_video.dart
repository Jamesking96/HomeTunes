// Videos (0.1.32): the Edit details dialog, for one video or several at once.
//
// Like the song and book editors, the changes are saved as edits in videos.json and laid over
// the file's own details; the video file itself is never changed, but with "Also save into .nfo
// files" ticked the details are also written into an .nfo beside it (widgets/save_nfo.dart).
// For one video every box can be
// changed or emptied, and "Undo my changes" goes back to what the file says. For several, a box
// whose value differs between them starts empty with "--:--" as its hint, and only boxes that are
// typed in are applied (titles can't be set for several at once, as they'd all get the same one).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';
import '../widgets/save_nfo.dart';
import 'video_pictures.dart' show PictureShapePicker;

/// Opens the editor for [videos] (one or more).
Future<void> showEditVideos(BuildContext context, List<VideoItem> videos) async {
  if (videos.isEmpty) return;
  await showDialog<void>(context: context, builder: (_) => _EditVideos(videos: videos));
}

class _EditVideos extends StatefulWidget {
  final List<VideoItem> videos;
  const _EditVideos({required this.videos});

  @override
  State<_EditVideos> createState() => _EditVideosState();
}

class _EditVideosState extends State<_EditVideos> {
  late final bool _several = widget.videos.length > 1;
  late final _title = TextEditingController(text: _several ? '' : widget.videos.single.title);
  late final _collection = TextEditingController(text: _common((v) => v.collection) ?? '');
  late final _year = TextEditingController(text: _common((v) => v.year?.toString()) ?? '');
  late final _genre = TextEditingController(text: _common((v) => v.genre) ?? '');
  late final _description = TextEditingController(text: _common((v) => v.description) ?? '');
  late final _season = TextEditingController(text: _common((v) => v.season?.toString()) ?? '');
  late final _episode = TextEditingController(text: _several ? '' : (widget.videos.single.episode?.toString() ?? ''));
  String? _numberError;
  String? _yearError;
  bool _saving = false;

  // Picture shape (Look): each video's own, or the usual one (null). [_shapeMixed]: several
  // videos that differ and no shape picked yet (then they're left as they are).
  late final VideoLibraryModel _model = context.read<VideoLibraryModel>();
  late final Set<PictureShape?> _startShapes = {for (final v in widget.videos) _model.ownShapeOf(v)};
  late PictureShape? _shape = _startShapes.length == 1 ? _startShapes.single : null;
  late bool _shapeMixed = _startShapes.length > 1;
  bool _shapeChanged = false;

  /// The value all the videos share, or null when they differ.
  String? _common(String? Function(VideoItem) get) {
    final values = {for (final v in widget.videos) get(v)};
    return values.length == 1 ? values.single : null;
  }

  /// "--:--" for a box whose value differs between the videos being edited.
  String? _hint(String? Function(VideoItem) get) => _several && _common(get) == null ? '--:--' : null;

  @override
  void dispose() {
    for (final c in [_title, _collection, _year, _genre, _description, _season, _episode]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _parseYear() {
    final t = _year.text.trim();
    if (t.isEmpty) return null;
    final y = int.tryParse(t);
    return (y != null && y >= 1800 && y <= 2200) ? y : -1;
  }

  Future<void> _save() async {
    final year = _parseYear();
    if (year == -1) {
      setState(() => _yearError = 'A year like 2019');
      return;
    }
    // Season and episode: whole numbers (0 = specials), or empty.
    int? number(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    final season = number(_season), episode = number(_episode);
    if ((_season.text.trim().isNotEmpty && (season == null || season < 0)) ||
        (_episode.text.trim().isNotEmpty && (episode == null || episode < 0))) {
      setState(() => _numberError = 'A number, like 2');
      return;
    }
    setState(() => _saving = true);
    final model = context.read<VideoLibraryModel>();
    final edits = <String, VideoEdit?>{};
    if (!_several) {
      final v = widget.videos.single;
      final raw = model.rawById(v.id) ?? v;
      edits[v.id] = VideoEdit.fromForm(
        raw,
        title: _title.text,
        collection: _collection.text,
        year: year,
        genre: _genre.text,
        description: _description.text,
        season: season,
        episode: episode,
        seasonKnown: true,
      );
    } else {
      // Several: only what was typed in is applied, on top of each video's own edit.
      String? typed(TextEditingController c, String? Function(VideoItem) get) {
        final t = c.text.trim();
        return t.isEmpty || t == _common(get) ? null : t;
      }

      final collection = typed(_collection, (v) => v.collection);
      final genre = typed(_genre, (v) => v.genre);
      final description = typed(_description, (v) => v.description);
      final newYear = year != null && year.toString() != _common((v) => v.year?.toString()) ? year : null;
      final newSeason = season != null && season.toString() != _common((v) => v.season?.toString()) ? season : null;
      for (final v in widget.videos) {
        final old = model.editOf(v.id) ?? const VideoEdit();
        edits[v.id] = old.merge(
          collection: collection,
          year: newYear,
          genre: genre,
          description: description,
          season: newSeason,
        );
      }
    }
    await model.setEdits(edits);
    if (_shapeChanged) await model.setShapes([for (final v in widget.videos) v.id], _shape);
    if (!mounted) return;
    saveNfoAfterEdit(context, widget.videos);
    Navigator.of(context).pop();
  }

  Future<void> _undo() async {
    await context.read<VideoLibraryModel>().setEdit(widget.videos.single.id, null);
    if (!mounted) return;
    saveNfoAfterEdit(context, widget.videos);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final hasEdit = !_several && model.editOf(widget.videos.single.id) != null;
    final raw = _several ? null : model.rawById(widget.videos.single.id);
    // What the file itself says, shown under a box when it's been changed.
    String? fileSays(String? value, String now) =>
        raw != null && (value ?? '') != now.trim() && (value ?? '').isNotEmpty ? 'File: $value' : null;

    return AlertDialog(
      title: Text(_several ? 'Edit ${widget.videos.length} videos' : 'Edit video details'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!_several)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.videos.single.path, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            TextField(
              key: const ValueKey('video-title'),
              controller: _title,
              enabled: !_several,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: _several ? 'Each keeps its own title' : null,
                helperText: fileSays(raw?.title, _title.text),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('video-collection'),
              controller: _collection,
              decoration: InputDecoration(
                labelText: 'Collection',
                hintText: _hint((v) => v.collection) ?? 'Groups videos together, e.g. a series or a trip',
                helperText: fileSays(raw?.collection, _collection.text),
                // Pick one that's already in use.
                suffixIcon: PopupMenuButton<String>(
                  tooltip: 'Choose a collection',
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (c) => setState(() => _collection.text = c),
                  itemBuilder: (_) => [for (final c in model.collectionNames) PopupMenuItem(value: c, child: Text(c))],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('video-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _yearError = null),
                  decoration: InputDecoration(labelText: 'Year', hintText: _hint((v) => v.year?.toString()), errorText: _yearError),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('video-genre'),
                  controller: _genre,
                  decoration: InputDecoration(labelText: 'Genre', hintText: _hint((v) => v.genre)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            // Season (0 = specials) and episode: where it's listed on its collection's page.
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('video-season'),
                  controller: _season,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _numberError = null),
                  decoration: InputDecoration(
                    labelText: 'Season',
                    hintText: _hint((v) => v.season?.toString()),
                    helperText: '0 = specials',
                    errorText: _numberError,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (!_several)
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: const ValueKey('video-episode'),
                    controller: _episode,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() => _numberError = null),
                    decoration: const InputDecoration(labelText: 'Episode'),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('video-description'),
              controller: _description,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(labelText: 'Description', hintText: _hint((v) => v.description)),
            ),
            const SizedBox(height: 12),
            // Look: the shape of its picture on the Videos tab.
            PictureShapePicker(
              title: _several ? 'Picture shape (Look)${_shapeMixed ? ': these differ' : ''}' : 'Picture shape (Look)',
              value: _shape,
              usual: model.library.videoPictureShape,
              mixed: _shapeMixed,
              onChanged: (s) => setState(() {
                _shape = s;
                _shapeMixed = false;
                _shapeChanged = true;
              }),
            ),
            if (_several)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('Only the boxes you type in are changed; the rest are left as they are.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            const SaveNfoCheckbox(),
          ]),
        ),
      ),
      actions: [
        if (hasEdit) TextButton(onPressed: _saving ? null : _undo, child: const Text('Undo my changes')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
