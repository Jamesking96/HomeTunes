// The "Edit song / Edit album / Edit N songs" dialog: change titles, artists, album names,
// track and disc numbers, year, genre and cover.
//
// Opened from a song's ⋮ menu, the album page's pencil button and multi-select. It works in three
// modes: one song (every field, blank = "use the file's value"), a whole album, or a selection of
// songs (only the shared fields, and only the ones actually changed are applied).
// Changes are stored as TrackEdits in LibraryModel (edits.json); the files themselves are only
// changed later if the user uses Settings > Your edits > Save edits into music files.
// Two helpers make album tidying easier: a single-song edit can also update the rest of its
// album, and an album edit can pull in "stray" songs listed as a separate album.
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
import 'info_lookup_dialog.dart';

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

/// The text fields the editor can show.
enum _Field { title, artist, album, albumArtist, trackNumber, discNumber, year, genre }

/// The editor itself. [albumMode] means "edit this album"; [fullScreen] picks the phone layout.
class _EditDetails extends StatefulWidget {
  final List<Track> tracks;
  final bool albumMode;
  final bool fullScreen;
  const _EditDetails({required this.tracks, required this.albumMode, required this.fullScreen});

  @override
  State<_EditDetails> createState() => _EditDetailsState();
}

class _EditDetailsState extends State<_EditDetails> {
  /// True when editing exactly one song (the only mode that shows every field).
  late final bool _single = widget.tracks.length == 1 && !widget.albumMode;
  /// Which fields to show in this mode, in order.
  late final List<_Field> _fields;
  final Map<_Field, TextEditingController> _ctrl = {};
  final Map<_Field, String> _initial = {};
  /// Fields where the songs being edited disagree; their box starts blank with a "Mixed" hint.
  final Set<_Field> _mixed = {};

  String? _newCover; // imported copy of a picked image
  /// True when the user chose to go back to the file's own cover.
  bool _resetCover = false;
  /// True while saving; disables the buttons so it can't be pressed twice.
  bool _saving = false;

  /// Single song: also give the rest of its album the album-wide changes.
  bool _updateAlbum = true;

  /// Single song: the other songs on the same album (found when the editor opens).
  late final List<Track> _albumSiblings;

  List<Track> get _tracks => widget.tracks;

  /// Details that belong to the whole album rather than one song.
  static const _albumFields = [_Field.album, _Field.albumArtist, _Field.year, _Field.genre];

  @override
  void initState() {
    super.initState();
    // Pick the fields: all of them for one song; album-level ones for an album or a selection.
    _fields = _single
        ? _Field.values
        : widget.albumMode
            ? const [_Field.album, _Field.albumArtist, _Field.artist, _Field.year, _Field.genre]
            : const [_Field.artist, _Field.album, _Field.albumArtist, _Field.year, _Field.genre];
    // Start each box with the value all the songs share, or blank if they differ.
    for (final f in _fields) {
      final values = _tracks.map((t) => _valueOf(t, f)).toSet();
      final common = values.length == 1 ? values.first : '';
      if (values.length > 1) _mixed.add(f);
      _initial[f] = common;
      _ctrl[f] = TextEditingController(text: common);
    }
    final first = _tracks.first;
    // For a single song, note the other songs on its album (used for "Also update the other…").
    _albumSiblings = _single
        ? [
            for (final t in context.read<LibraryModel>().tracks)
              if (t.albumKey == first.albumKey && t.id != first.id) t
          ]
        : const [];
    _strays = widget.albumMode ? _findStrays(context.read<LibraryModel>().tracks) : const [];
  }

  /// Album mode: songs with this album's title that show up as a separate
  /// album because their album artist differs (typically "A feat. B" songs).
  late final List<Track> _strays;
  /// Whether the strays should be pulled into this album on save (the tick box).
  bool _includeStrays = true;

  /// Finds the "stray" songs: same album title, different album key, and the album artist's name
  /// appears in their artist or album artist (e.g. "Artist feat. Someone").
  List<Track> _findStrays(List<Track> all) {
    final first = _tracks.first;
    final title = first.album.toLowerCase();
    final artist = first.albumArtist.toLowerCase();
    // Don't guess for untitled or unknown-artist albums: too many false matches.
    if (title.isEmpty || artist.isEmpty || artist == 'unknown artist') return const [];
    return [
      for (final t in all)
        if (t.album.toLowerCase() == title &&
            t.albumKey != first.albumKey &&
            (t.albumArtist.toLowerCase().contains(artist) || t.artist.toLowerCase().contains(artist)))
          t
    ];
  }

  /// Single song: the album-wide details that differ from when the editor
  /// opened (blank boxes don't count: they mean "use this song's file").
  List<_Field> get _changedAlbumFields => [
        for (final f in _albumFields)
          if (_ctrl[f]!.text.trim().isNotEmpty && _ctrl[f]!.text.trim() != _initial[f]) f
      ];

  /// Whether the cover has been changed (new one picked, or reset) in this editor.
  bool get _albumCoverChanged => _newCover != null || _resetCover;

  /// Whether to show the "Also update the other songs on this album" tick box.
  bool get _offerAlbumUpdate =>
      _single && _albumSiblings.isNotEmpty && (_changedAlbumFields.isNotEmpty || _albumCoverChanged);

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The value of field [f] for song [t], as text for a box.
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

  /// Number-only fields (digits only on the keyboard).
  static bool _isNumber(_Field f) => f == _Field.trackNumber || f == _Field.discNumber || f == _Field.year;

  /// The dialog's title, which depends on the mode.
  String get _heading {
    if (_single) return 'Edit song';
    if (widget.albumMode) return 'Edit album';
    return 'Edit ${_tracks.length} songs';
  }

  /// "Choose image…": pick a picture file and copy it into the app's own cover folder
  /// (so the cover still works if the original picture is moved).
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

  /// "Find online…" for the cover: searches by album artist (or artist) and album.
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

  /// Maps an editor field to the matching kind of online lookup.
  static InfoField _infoField(_Field f) => switch (f) {
        _Field.title => InfoField.title,
        _Field.artist => InfoField.artist,
        _Field.album => InfoField.album,
        _Field.albumArtist => InfoField.albumArtist,
        _Field.trackNumber => InfoField.trackNumber,
        _Field.discNumber => InfoField.discNumber,
        _Field.year => InfoField.year,
        _Field.genre => InfoField.genre,
      };

  /// Looks up one field online (by song for a single song, by album otherwise)
  /// and puts the chosen value in the box. Nothing is saved until Save.
  Future<void> _lookUp(_Field f) async {
    final albumArtist = _current(_Field.albumArtist);
    final choice = await showInfoLookup(
      context,
      field: _infoField(f),
      songMode: _single,
      title: _single ? _current(_Field.title) : null,
      artist: _single ? _current(_Field.artist) : (albumArtist.isNotEmpty ? albumArtist : _current(_Field.artist)),
      album: _current(_Field.album),
    );
    if (choice == null || !mounted) return;
    setState(() => _ctrl[f]!.text = choice.value);
  }

  /// Saves the changes. One song and several songs are handled quite differently; see below.
  Future<void> _save() async {
    final lib = context.read<LibraryModel>();
    setState(() => _saving = true);

    // Blank box = no value (for one song that means "use the file's value").
    String? text(_Field f) {
      final v = _ctrl[f]!.text.trim();
      return v.isEmpty ? null : v;
    }

    int? number(_Field f) => int.tryParse(_ctrl[f]!.text.trim());

    // ---- One song ----
    // The whole edit is replaced by what's in the boxes (lyrics are kept by setEdit).
    if (_single) {
      final t = _tracks.first;
      final original = lib.originalById(t.id);
      // Work out the album-wide changes before this song's edit regroups it.
      final alsoAlbum = _offerAlbumUpdate && _updateAlbum;
      final albumFields = _changedAlbumFields;
      final siblingIds = [for (final s in _albumSiblings) s.id];
      // Siblings that showed the same cover as this song; they follow a
      // "use the file's cover" reset.
      final sharedCoverIds = [
        for (final s in _albumSiblings)
          if (s.art == t.art) s.id
      ];
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
      if (alsoAlbum) {
        // Songs that shared this song's cover go back to their files' covers too.
        if (_resetCover) await lib.resetCovers(sharedCoverIds);
        String? v(_Field f) => albumFields.contains(f) ? text(f) : null;
        final patch = TrackEdit(
          album: v(_Field.album),
          albumArtist: v(_Field.albumArtist),
          year: albumFields.contains(_Field.year) ? number(_Field.year) : null,
          genre: v(_Field.genre),
          art: _newCover,
        );
        if (!patch.isEmpty) await lib.editMany(siblingIds, patch);
      }
    // ---- An album or several songs ----
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

      // Reset covers first, so a newly picked cover in the patch wins.
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
      if (_strays.isNotEmpty && _includeStrays) {
        // Bring the stray songs into this album, with the same changes.
        // Strays also get the album name and album artist, so they group with this album
        // afterwards. If the album artist box is blank, use the current album artist.
        final albumArtist = _ctrl[_Field.albumArtist]!.text.trim();
        await lib.editMany(
          [for (final t in _strays) t.id],
          patch.mergedWith(TrackEdit(
            album: _ctrl[_Field.album]!.text.trim().isEmpty ? null : _ctrl[_Field.album]!.text.trim(),
            albumArtist: albumArtist.isEmpty ? _tracks.first.albumArtist : albumArtist,
          )),
        );
      }
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// "Reset to file details": removes all the user's edits for these songs.
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

    // ---- The form: cover section, one text box per field, tick boxes, notes, reset button ----
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
              // A separate "find online" button for each detail.
              suffixIcon: context.watch<LibraryModel>().onlineDetails
                  ? IconButton(
                      tooltip: 'Find ${_label(f).toLowerCase()} online',
                      icon: const Icon(Icons.travel_explore, size: 20),
                      onPressed: _saving ? null : () => _lookUp(f),
                    )
                  : null,
              labelText: _label(f),
              // "Mixed" boxes start blank; leaving them blank keeps each song's own value.
              hintText: _mixed.contains(f) ? 'Mixed – leave blank to keep each song\'s own' : null,
              helperText: _helperFor(f, lib),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Single song: offer to copy album-wide changes (album, album artist, year, genre, cover)
        // to the other songs on the album.
        if (_offerAlbumUpdate)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _updateAlbum,
            onChanged: _saving ? null : (v) => setState(() => _updateAlbum = v ?? true),
            title: Text(
              'Also update the other ${_albumSiblings.length} '
              'song${_albumSiblings.length == 1 ? '' : 's'} on "${_tracks.first.album}"',
            ),
            subtitle: Text(
              'Changes to: ${[
                for (final f in _changedAlbumFields) _label(f).toLowerCase(),
                if (_albumCoverChanged) 'cover',
              ].join(', ')}',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
        // Album mode: offer to pull in the stray songs found when the editor opened.
        if (_strays.isNotEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _includeStrays,
            onChanged: _saving ? null : (v) => setState(() => _includeStrays = v ?? true),
            title: Text(
              'Include ${_strays.length} more song${_strays.length == 1 ? '' : 's'} from "${_tracks.first.album}"',
            ),
            subtitle: Text(
              '${_strays.take(3).map((t) => t.title).join(', ')}${_strays.length > 3 ? '…' : ''} – '
              'listed as a separate album because of a different album artist. '
              'They\'ll join this album and get the same changes.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
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

    // Phone layout: an app bar with a close (x) button and Save.
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
    // Dialog layout: title bar, the scrolling form, and Cancel / Save at the bottom.
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

  /// The cover row: a preview (new pick, the file's own cover after a reset, or the current
  /// cover) with Choose image / Find online / "Use the file's own cover" buttons.
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
            // Only offer an online search when there's an artist or album to search for.
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
