// Edit collection, for one collection (showEditCollection) or several (showEditCollections). Like
// editing an album, a new name, category, year or genre is saved on every video in it (as edits,
// the files aren't changed); the description belongs to the collection. Split out of
// video_collection_screen.dart in refactor phase 6 (9 Oct 2026), unchanged.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/video_item.dart';
import '../../../state/mixed_value.dart';
import '../../../state/video_library_model.dart';
import '../../theme.dart';
import '../../widgets/save_nfo.dart';
import '../video_pictures.dart';

/// Edit collection for one or several (select mode on the Collections tab). For several, only
/// what's typed or picked is changed: category, year, genre and poster shape (a name or a
/// description for several at once wouldn't make sense).
Future<void> showEditCollections(BuildContext context, List<VideoCollection> list) async {
  if (list.isEmpty) return;
  if (list.length == 1) {
    await showEditCollection(context, list.single);
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _EditSeveralCollections(collections: list));
}

class _EditSeveralCollections extends StatefulWidget {
  final List<VideoCollection> collections;
  const _EditSeveralCollections({required this.collections});

  @override
  State<_EditSeveralCollections> createState() => _EditSeveralCollectionsState();
}

class _EditSeveralCollectionsState extends State<_EditSeveralCollections> {
  late final List<VideoCollection> _list = widget.collections;
  late final _category = TextEditingController(text: _common((c) => c.category) ?? '');
  late final _year = TextEditingController(text: _common((c) => c.year?.toString()) ?? '');
  late final _genre = TextEditingController(text: _common((c) => c.genre) ?? '');
  late final VideoLibraryModel _model = context.read<VideoLibraryModel>();
  late final Set<PictureShape?> _startShapes = {for (final c in _list) _model.ownCollectionShapeOf(c)};
  late PictureShape? _shape = _startShapes.length == 1 ? _startShapes.single : null;
  late bool _shapeMixed = _startShapes.length > 1;
  bool _shapeChanged = false;
  String? _yearError;
  bool _saving = false;

  /// The value all the collections share, or null when they differ (or all have none).
  String? _common(String? Function(VideoCollection) get) => _shared(get).value;

  // Blank counts as "none", so collections that are all blank share it (8 Oct: like the song and
  // book editors, the box is then plain, not --:--).
  ({bool differ, String? value}) _shared(String? Function(VideoCollection) get) => sharedValue<String?>([
        for (final c in _list)
          if (get(c) case final s? when s.isNotEmpty) s else null,
      ]);

  String? _hint(String? Function(VideoCollection) get) => _shared(get).differ ? differentMarker : null;

  @override
  void dispose() {
    for (final t in [_category, _year, _genre]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final y = _year.text.trim();
    final year = y.isEmpty ? null : int.tryParse(y);
    if (y.isNotEmpty && (year == null || year < 1800 || year > 2200)) {
      setState(() => _yearError = 'A year like 2019');
      return;
    }
    setState(() => _saving = true);
    String? typed(TextEditingController t, String? Function(VideoCollection) get) {
      final v = t.text.trim();
      return v.isEmpty || v == _common(get) ? null : v;
    }

    final category = typed(_category, (c) => c.category);
    final genre = typed(_genre, (c) => c.genre);
    final newYear = year != null && '$year' != _common((c) => c.year?.toString()) ? year : null;
    for (final c in _list) {
      if (_shapeChanged) await _model.setCollectionShape(c, _shape);
      if (category != null || genre != null || newYear != null) {
        await _model.editCollection(c, category: category, genre: genre, year: newYear);
      }
    }
    if (!mounted) return;
    saveNfoAfterEdit(context, [for (final c in _list) ...c.videos]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = {for (final x in _model.collections) if (x.category != null) x.category!}.toList()..sort();
    return AlertDialog(
      title: Text('Edit ${_list.length} collections'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_list.map((c) => c.name).join(', '),
                maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collections-category'),
              controller: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: _hint((c) => c.category) ?? 'TV, Anime, Films…',
                suffixIcon: categories.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a category',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (x) => setState(() => _category.text = x),
                        itemBuilder: (_) => [for (final x in categories) PopupMenuItem(value: x, child: Text(x))],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('collections-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _yearError = null),
                  decoration: InputDecoration(labelText: 'Year', hintText: _hint((c) => c.year?.toString()), errorText: _yearError),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('collections-genre'),
                  controller: _genre,
                  decoration: InputDecoration(labelText: 'Genre', hintText: _hint((c) => c.genre)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            PictureShapePicker(
              title: 'Poster shape (Look)${_shapeMixed ? ': these differ' : ''}',
              value: _shape,
              usual: _model.library.collectionPictureShape,
              mixed: _shapeMixed,
              onChanged: (s) => setState(() {
                _shape = s;
                _shapeMixed = false;
                _shapeChanged = true;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Only what you type or pick is changed; the rest is left as it is. Changes are saved on every '
                  'video in these collections.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            const SaveNfoCheckbox(),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Edit collection. Returns the new name if it was renamed, or null.
Future<String?> showEditCollection(BuildContext context, VideoCollection c) =>
    showDialog<String>(context: context, builder: (_) => _EditCollection(collection: c));

class _EditCollection extends StatefulWidget {
  final VideoCollection collection;
  const _EditCollection({required this.collection});

  @override
  State<_EditCollection> createState() => _EditCollectionState();
}

class _EditCollectionState extends State<_EditCollection> {
  late final VideoCollection c = widget.collection;
  late final _name = TextEditingController(text: c.name);
  late final _category = TextEditingController(text: c.category ?? '');
  late final _year = TextEditingController(text: c.year?.toString() ?? '');
  late final _genre = TextEditingController(text: c.genre ?? '');
  late final _description = TextEditingController(text: c.description ?? '');
  String? _yearError;
  bool _saving = false;
  // Look: the collection's own picture shape, or the usual one (null).
  late PictureShape? _shape = context.read<VideoLibraryModel>().ownCollectionShapeOf(c);

  @override
  void dispose() {
    for (final t in [_name, _category, _year, _genre, _description]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final y = _year.text.trim();
    final year = y.isEmpty ? null : int.tryParse(y);
    if (y.isNotEmpty && (year == null || year < 1800 || year > 2200)) {
      setState(() => _yearError = 'A year like 2019');
      return;
    }
    setState(() => _saving = true);
    final model = context.read<VideoLibraryModel>();
    final name = _name.text.trim();
    final category = _category.text.trim();
    final genre = _genre.text.trim();
    // Before a rename, which carries the shape across.
    if (_shape != model.ownCollectionShapeOf(c)) await model.setCollectionShape(c, _shape);
    await model.editCollection(
      c,
      name: name.isNotEmpty && name != c.name ? name : null,
      category: category.isNotEmpty && category != c.category ? category : null,
      clearCategory: category.isEmpty && c.category != null,
      year: year != null && year != c.year ? year : null,
      clearYear: year == null && c.year != null,
      genre: genre.isNotEmpty && genre != c.genre ? genre : null,
      clearGenre: genre.isEmpty && c.genre != null,
      description: _description.text.trim() != (c.description ?? '') ? _description.text : null,
    );
    if (!mounted) return;
    saveNfoAfterEdit(context, c.videos);
    Navigator.of(context).pop(name.isNotEmpty && name != c.name ? name : null);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final categories = {for (final x in model.collections) if (x.category != null) x.category!}.toList()..sort();
    return AlertDialog(
      title: const Text('Edit collection'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Changes are saved on all ${c.videos.length} videos in this collection.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', helperText: 'Another collection\'s name joins the two'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-category'),
              controller: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'TV, Anime, Films…',
                suffixIcon: categories.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a category',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (x) => setState(() => _category.text = x),
                        itemBuilder: (_) => [for (final x in categories) PopupMenuItem(value: x, child: Text(x))],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('collection-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _yearError = null),
                  decoration: InputDecoration(labelText: 'Year', errorText: _yearError),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('collection-genre'),
                  controller: _genre,
                  decoration: const InputDecoration(labelText: 'Genre'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-description'),
              controller: _description,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            PictureShapePicker(
              title: 'Poster shape (Look)',
              value: _shape,
              usual: model.library.collectionPictureShape,
              onChanged: (s) => setState(() => _shape = s),
            ),
            const SizedBox(height: 8),
            const SaveNfoCheckbox(),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
