// Saving the song / album editor (as edits, and for several albums the cover) and its Reset.
// Part of edit_details.dart (refactor phase 6, 9 Oct 2026: moved here unchanged, as an extension
// on the editor's state).
part of '../edit_details.dart';

extension _EditDetailsSaving on _EditDetailsState {
  /// Saves the changes. One song and several songs are handled quite differently; see below.
  Future<void> _saveChanges() async {
    final lib = context.read<LibraryModel>();

    // Blank box = no value. (For one song, title, artist, album and album artist can't be
    // blank, so a blank box there means "use the file's value".)
    String? text(_Field f) {
      final v = _ctrl[f]!.text.trim();
      return v.isEmpty ? null : v;
    }

    int? number(_Field f) => int.tryParse(_ctrl[f]!.text.trim());

    // ---- One song ----
    // The whole edit is replaced by what's in the boxes (lyrics and audiobook details are kept
    // by setEdit). Track number, disc number, year and genre can be emptied to remove them, even
    // when the file has a value (0.1.16); "Reset to file details" brings the file's values back.
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
          cleared: {
            for (final (f, name) in const [
              (_Field.trackNumber, 'trackNumber'),
              (_Field.discNumber, 'discNumber'),
              (_Field.year, 'year'),
              (_Field.genre, 'genre'),
            ])
              if (_ctrl[f]!.text.trim().isEmpty) name,
          },
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
      // A box that showed a value all the songs shared and has been emptied removes that
      // detail (year and genre only; the others can't be blank). A --:-- box left empty keeps
      // each song's own value.
      bool emptied(_Field f) =>
          _fields.contains(f) && !_mixed.contains(f) && (_initial[f] ?? '').isNotEmpty && _ctrl[f]!.text.trim().isEmpty;
      final patch = TrackEdit(
        artist: changedText(_Field.artist),
        album: changedText(_Field.album),
        albumArtist: changedText(_Field.albumArtist),
        year: changedNumber(_Field.year),
        genre: changedText(_Field.genre),
        art: _newCover,
        cleared: {
          if (emptied(_Field.year)) 'year',
          if (emptied(_Field.genre)) 'genre',
        },
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
            : _manyAlbums
                ? 'Your changes to these ${widget.albumCount} albums will be removed and they will show the details from '
                    'the music files again.'
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
}
