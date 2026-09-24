import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../models/track_edit.dart';
import '../../state/library_model.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import 'cover_search_dialog.dart';

/// Opens the editor for one song, a whole album ([album] = true) or several
/// selected songs. Changes are saved in HomeTunes only; music files are never
/// modified. Returns true if anything was saved.
Future<bool> showEditDetails(BuildContext context, List<Track> tracks, {bool album = false}) async {
  if (tracks.isEmpty) return false;
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) {
      final editor = _EditDetails(tracks: tracks, albumMode: album, fullScreen: !wide);
      return wide
          ? Dialog(
              backgroundColor: AppColors.surface,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760), child: editor),
            )
          : Dialog.fullscreen(backgroundColor: AppColors.bg, child: editor);
    },
  );
  return saved ?? false;
}

enum _Field { title, artist, album, albumArtist, trackNumber, discNumber, year, genre }

class _EditDetails extends StatefulWidget {
  final List<Track> tracks;
  final bool albumMode;
  final bool fullScreen;
  const _EditDetails({required this.tracks, required this.albumMode, required this.fullScreen});

  @override
  State<_EditDetails> createState() => _EditDetailsState();
}

class _EditDetailsState extends State<_EditDetails> {
  late final bool _single = widget.tracks.length == 1 && !widget.albumMode;
  late final List<_Field> _fields;
  final Map<_Field, TextEditingController> _ctrl = {};
  final Map<_Field, String> _initial = {};
  final Set<_Field> _mixed = {};

  String? _newCover; // imported copy of a picked image
  bool _resetCover = false;
  bool _saving = false;

  List<Track> get _tracks => widget.tracks;

  @override
  void initState() {
    super.initState();
    _fields = _single
        ? _Field.values
        : widget.albumMode
            ? const [_Field.album, _Field.albumArtist, _Field.artist, _Field.year, _Field.genre]
            : const [_Field.artist, _Field.album, _Field.albumArtist, _Field.year, _Field.genre];
    for (final f in _fields) {
      final values = _tracks.map((t) => _valueOf(t, f)).toSet();
      final common = values.length == 1 ? values.first : '';
      if (values.length > 1) _mixed.add(f);
      _initial[f] = common;
      _ctrl[f] = TextEditingController(text: common);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _valueOf(Track t, _Field f) => switch (f) {
        _Field.title => t.title,
        _Field.artist => t.artist,
        _Field.album => t.album,
        _Field.albumArtist => t.albumArtist,
        _Field.trackNumber => t.trackNumber?.toString() ?? '',
        _Field.discNumber => t.discNumber?.toString() ?? '',
        _Field.year => t.year?.toString() ?? '',
        _Field.genre => t.genre ?? '',
      };

  static String _label(_Field f) => switch (f) {
        _Field.title => 'Title',
        _Field.artist => 'Artist',
        _Field.album => 'Album',
        _Field.albumArtist => 'Album artist',
        _Field.trackNumber => 'Track number',
        _Field.discNumber => 'Disc number',
        _Field.year => 'Year',
        _Field.genre => 'Genre',
      };

  static bool _isNumber(_Field f) => f == _Field.trackNumber || f == _Field.discNumber || f == _Field.year;

  String get _heading {
    if (_single) return 'Edit song';
    if (widget.albumMode) return 'Edit album';
    return 'Edit ${_tracks.length} songs';
  }

  Future<void> _pickCover() async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a cover image');
      final path = file?.path;
      if (path == null) return;
      final copy = await lib.importCover(path);
      if (!mounted) return;
      setState(() {
        _newCover = copy;
        _resetCover = false;
      });
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that image: $e')));
    }
  }

  /// Current text of a field, falling back to the (first) song's value.
  String _current(_Field f) {
    final c = _ctrl[f];
    final v = c?.text.trim() ?? '';
    return v.isNotEmpty ? v : _valueOf(_tracks.first, f);
  }

  Future<void> _findOnline() async {
    final albumArtist = _current(_Field.albumArtist);
    final path = await showCoverSearch(
      context,
      artist: albumArtist.isNotEmpty ? albumArtist : _current(_Field.artist),
      album: _current(_Field.album),
      title: _single ? _current(_Field.title) : null,
    );
    if (path == null || !mounted) return;
    setState(() {
      _newCover = path;
      _resetCover = false;
    });
  }

  Future<void> _save() async {
    final lib = context.read<LibraryModel>();
    setState(() => _saving = true);

    String? text(_Field f) {
      final v = _ctrl[f]!.text.trim();
      return v.isEmpty ? null : v;
    }

    int? number(_Field f) => int.tryParse(_ctrl[f]!.text.trim());

    if (_single) {
      final t = _tracks.first;
      final original = lib.originalById(t.id);
      // Keep an existing custom cover unless a new one was picked or it was reset.
      final keptArt = (original != null && t.art != original.art) ? t.art : null;
      await lib.setEdit(
        t.id,
        TrackEdit(
          title: text(_Field.title),
          artist: text(_Field.artist),
          album: text(_Field.album),
          albumArtist: text(_Field.albumArtist),
          trackNumber: number(_Field.trackNumber),
          discNumber: number(_Field.discNumber),
          year: number(_Field.year),
          genre: text(_Field.genre),
          art: _resetCover ? null : (_newCover ?? keptArt),
        ),
      );
    } else {
      // Only fields the user actually changed are applied to every song.
      String? changedText(_Field f) {
        if (!_fields.contains(f)) return null;
        final v = _ctrl[f]!.text.trim();
        return (v.isEmpty || v == _initial[f]) ? null : v;
      }

      int? changedNumber(_Field f) {
        final v = changedText(f);
        return v == null ? null : int.tryParse(v);
      }

      final ids = [for (final t in _tracks) t.id];
      if (_resetCover) await lib.resetCovers(ids);
      final patch = TrackEdit(
        artist: changedText(_Field.artist),
        album: changedText(_Field.album),
        albumArtist: changedText(_Field.albumArtist),
        year: changedNumber(_Field.year),
        genre: changedText(_Field.genre),
        art: _newCover,
      );
      if (!patch.isEmpty) await lib.editMany(ids, patch);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _resetAll() async {
    final lib = context.read<LibraryModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to file details?'),
        content: Text(_single
            ? 'Your changes to this song will be removed and it will show the details from the music file again.'
            : 'Your changes to these ${_tracks.length} songs will be removed and they will show the details from the music files again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await lib.resetEdits([for (final t in _tracks) t.id]);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final anyEdited = _tracks.any((t) => lib.isEdited(t.id));
    final anyCustomCover = _tracks.any((t) {
      final o = lib.originalById(t.id);
      return o != null && t.art != o.art;
    });

    final form = ListView(
      shrinkWrap: !widget.fullScreen,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _coverSection(anyCustomCover),
        const SizedBox(height: 16),
        for (final f in _fields) ...[
          TextField(
            controller: _ctrl[f],
            keyboardType: _isNumber(f) ? TextInputType.number : TextInputType.text,
            inputFormatters: _isNumber(f) ? [FilteringTextInputFormatter.digitsOnly] : null,
            textCapitalization: _isNumber(f) ? TextCapitalization.none : TextCapitalization.words,
            // Refresh the "In file: …" hint as you type.
            onChanged: _single ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: _label(f),
              hintText: _mixed.contains(f) ? 'Mixed – leave blank to keep each song\'s own' : null,
              helperText: _helperFor(f, lib),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        Text(
          'Changes are saved in HomeTunes only – your music files aren\'t modified.'
          '${_single ? ' Leave a field blank to use the value from the file.' : ''}',
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        if (anyEdited) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _resetAll,
              icon: const Icon(Icons.restore),
              label: const Text('Reset to file details'),
            ),
          ),
        ],
      ],
    );

    final saveButton = FilledButton(
      onPressed: _saving ? null : _save,
      child: _saving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Save'),
    );

    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
          title: Text(_heading),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: saveButton)],
        ),
        body: form,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
        child: Row(children: [
          Expanded(child: Text(_heading, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
        ]),
      ),
      Flexible(child: form),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          const SizedBox(width: 8),
          saveButton,
        ]),
      ),
    ]);
  }

  /// Under a single song's field, show the file's value when it's been changed.
  String? _helperFor(_Field f, LibraryModel lib) {
    if (!_single) return null;
    final original = lib.originalById(_tracks.first.id);
    if (original == null) return null;
    final fileValue = _valueOf(original, f);
    if (fileValue == _ctrl[f]!.text.trim() || fileValue.isEmpty) return null;
    return 'In file: $fileValue';
  }

  Widget _coverSection(bool anyCustomCover) {
    Widget preview;
    if (_newCover != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(_newCover!), width: 120, height: 120, fit: BoxFit.cover),
      );
    } else if (_resetCover) {
      final lib = context.read<LibraryModel>();
      preview = Artwork(track: lib.originalById(_tracks.first.id), size: 120, radius: 6, placeholder: Icons.album);
    } else {
      preview = Artwork(track: _tracks.first, size: 120, radius: 6, placeholder: Icons.album);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      preview,
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cover', style: TextStyle(fontWeight: FontWeight.w600)),
          if (!_single)
            Text(
              _tracks.length == 1 ? 'Applies to this song' : 'Applies to all ${_tracks.length} songs',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickCover,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Choose image…'),
            ),
            if (context.watch<LibraryModel>().onlineCovers &&
                (_current(_Field.artist).isNotEmpty || _current(_Field.album).isNotEmpty))
              OutlinedButton.icon(
                onPressed: _saving ? null : _findOnline,
                icon: const Icon(Icons.travel_explore),
                label: const Text('Find online…'),
              ),
          ]),
          if ((anyCustomCover || _newCover != null) && !_resetCover)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                        _newCover = null;
                        _resetCover = true;
                      }),
              child: const Text('Use the file\'s own cover'),
            ),
        ]),
      ),
    ]);
  }
}
