import 'package:flutter/material.dart';

import '../../services/music_info.dart';
import '../theme.dart';

/// Song/album details that can be looked up online.
enum InfoField { title, artist, album, albumArtist, year, genre, trackNumber, discNumber }

extension InfoFieldLabel on InfoField {
  String get label => switch (this) {
        InfoField.title => 'title',
        InfoField.artist => 'artist',
        InfoField.album => 'album',
        InfoField.albumArtist => 'album artist',
        InfoField.year => 'year',
        InfoField.genre => 'genre',
        InfoField.trackNumber => 'track number',
        InfoField.discNumber => 'disc number',
      };
}

/// One value found online, with where it came from.
class InfoChoice {
  final String value;
  final String detail;

  /// The album it came from (album searches only), e.g. for track lists.
  final AlbumMatch? album;
  const InfoChoice(this.value, this.detail, {this.album});
}

/// Looks up one [field] online and lets the user pick a value.
///
/// [songMode]: search for the song (needs a title) – for a single song.
/// Otherwise search for the album – for album pages / several songs.
/// Returns the chosen value (and its album), or null.
Future<InfoChoice?> showInfoLookup(
  BuildContext context, {
  required InfoField field,
  required bool songMode,
  String? title,
  String? artist,
  String? album,
}) {
  return showDialog<InfoChoice>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _InfoLookupDialog(
      field: field,
      songMode: songMode,
      title: title ?? '',
      artist: artist ?? '',
      album: album ?? '',
    ),
  );
}

class _InfoLookupDialog extends StatefulWidget {
  final InfoField field;
  final bool songMode;
  final String title, artist, album;
  const _InfoLookupDialog({
    required this.field,
    required this.songMode,
    required this.title,
    required this.artist,
    required this.album,
  });

  @override
  State<_InfoLookupDialog> createState() => _InfoLookupDialogState();
}

class _InfoLookupDialogState extends State<_InfoLookupDialog> {
  final _search = MusicInfoSearch();
  late final _title = TextEditingController(text: widget.title);
  late final _artist = TextEditingController(text: widget.artist);
  late final _album = TextEditingController(text: widget.album);

  List<InfoChoice>? _choices;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _search.close();
    super.dispose();
  }

  String _where(String album, String artist, int? year) =>
      [if (album.isNotEmpty) album, if (artist.isNotEmpty) artist, if (year != null) '$year'].join(' · ');

  /// Adds [value] once; later sources for the same value are ignored.
  void _add(List<InfoChoice> out, Set<String> seen, String? value, String detail, {AlbumMatch? album}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || !seen.add(v.toLowerCase())) return;
    out.add(InfoChoice(v, detail, album: album));
  }

  Future<List<InfoChoice>> _songChoices() async {
    final matches = await _search.searchSongs(
      title: _title.text.trim(),
      artist: _artist.text.trim(),
      album: _album.text.trim(),
    );
    final out = <InfoChoice>[];
    final seen = <String>{};
    if (widget.field == InfoField.genre) {
      // Genres come from the album; check the best few albums the song is on.
      final ids = <String>{};
      for (final m in matches) {
        if (m.releaseGroupId.isEmpty || !ids.add(m.releaseGroupId)) continue;
        for (final g in await _search.genresFor(m.releaseGroupId)) {
          _add(out, seen, g, 'from ${_where(m.album, m.albumArtist, m.year)}');
        }
        if (ids.length >= 3) break;
      }
      return out;
    }
    for (final m in matches) {
      final value = switch (widget.field) {
        InfoField.title => m.title,
        InfoField.artist => m.artist,
        InfoField.album => m.album,
        InfoField.albumArtist => m.albumArtist,
        InfoField.year => m.year?.toString(),
        InfoField.trackNumber => m.trackNumber?.toString(),
        InfoField.discNumber => m.discNumber?.toString(),
        InfoField.genre => null,
      };
      // Track/disc numbers depend on the album, so keep one entry per album.
      final perAlbum = widget.field == InfoField.trackNumber || widget.field == InfoField.discNumber;
      if (perAlbum) {
        if (value == null) continue;
        final key = '${m.album}|${m.year}'.toLowerCase();
        if (!seen.add(key)) continue;
        out.add(InfoChoice(value, 'on ${_where(m.album, m.albumArtist, m.year)}'));
      } else {
        _add(out, seen, value, 'from ${_where(m.album, m.artist, m.year)}');
      }
    }
    return out;
  }

  Future<List<InfoChoice>> _albumChoices() async {
    final albums = await _search.searchAlbums(artist: _artist.text.trim(), album: _album.text.trim());
    final out = <InfoChoice>[];
    final seen = <String>{};
    if (widget.field == InfoField.genre) {
      for (final a in albums.take(3)) {
        for (final g in await _search.genresFor(a.id)) {
          _add(out, seen, g, 'from ${_where(a.title, a.artist, a.year)}', album: a);
        }
      }
      return out;
    }
    if (widget.field == InfoField.trackNumber) {
      // Choosing an album here means "use this album's track list".
      return [
        for (final a in albums)
          InfoChoice(a.title, _where('', a.artist, a.year) + (a.type != null ? ' · ${a.type}' : ''), album: a),
      ];
    }
    for (final a in albums) {
      final value = switch (widget.field) {
        InfoField.album => a.title,
        InfoField.artist || InfoField.albumArtist => a.artist,
        InfoField.year => a.year?.toString(),
        _ => null,
      };
      _add(out, seen, value, 'from ${_where(a.title, a.artist, a.year)}', album: a);
    }
    return out;
  }

  Future<void> _run() async {
    if (widget.songMode && _title.text.trim().isEmpty) {
      setState(() => _error = 'Enter the song title to search.');
      return;
    }
    if (!widget.songMode && _artist.text.trim().isEmpty && _album.text.trim().isEmpty) {
      setState(() => _error = 'Enter an artist or album name to search.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = widget.songMode ? await _songChoices() : await _albumChoices();
      if (!mounted) return;
      setState(() {
        _choices = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t search online. Check your internet connection.\n($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    final what = widget.field == InfoField.trackNumber && !widget.songMode ? 'track numbers' : widget.field.label;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)));
    } else if (choices == null || choices.isEmpty) {
      body = const Center(
        child: Text('Nothing found. Try adjusting the search.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
      );
    } else {
      body = ListView.separated(
        itemCount: choices.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = choices[i];
          return ListTile(
            title: Text(c.value, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(c.detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, c),
          );
        },
      );
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('Find $what online',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
              if (widget.songMode) _box(_title, 'Song title'),
              _box(_artist, 'Artist'),
              _box(_album, 'Album'),
              IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _loading ? null : _run),
            ]),
            const SizedBox(height: 12),
            Expanded(child: body),
            const SizedBox(height: 6),
            Text(
              widget.field == InfoField.trackNumber && !widget.songMode
                  ? 'Pick the matching album; its track list is matched to your songs by title. Info from MusicBrainz.'
                  : 'Tap a value to use it. Info from MusicBrainz.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _box(TextEditingController c, String label) => SizedBox(
        width: 160,
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: label, isDense: true),
          onSubmitted: (_) => _run(),
        ),
      );
}
