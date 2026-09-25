// The "Find cover online" dialog for songs and albums.
//
// It searches MusicBrainz for matching releases and shows their covers from the Cover Art Archive
// (the web side is in services/cover_search.dart). Tapping a cover downloads the full image and
// saves a copy in the app's own cover folder through LibraryModel.importCoverBytes; the dialog
// then returns that file's path. Callers (edit_details.dart, the album page's "no cover" prompt)
// store the path as a TrackEdit, so nothing is written into the music files.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/cover_search.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Searches online for a cover matching [artist] / [album] (or [title]) and
/// lets the user pick one. Returns the saved image's path, or null.
Future<String?> showCoverSearch(BuildContext context, {String? artist, String? album, String? title}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _CoverSearchDialog(artist: artist ?? '', album: album ?? '', title: title ?? ''),
  );
}

/// The dialog itself. [title] (a song title) is optional and only helps the search.
class _CoverSearchDialog extends StatefulWidget {
  final String artist, album, title;
  const _CoverSearchDialog({required this.artist, required this.album, required this.title});

  @override
  State<_CoverSearchDialog> createState() => _CoverSearchDialogState();
}

class _CoverSearchDialogState extends State<_CoverSearchDialog> {
  /// Does the web requests; closed when the dialog goes away.
  final _search = CoverSearch();
  late final _artist = TextEditingController(text: widget.artist);
  late final _album = TextEditingController(text: widget.album);

  /// Search results, or null before the first search has finished.
  List<CoverCandidate>? _results;
  /// True while searching.
  bool _loading = false;
  /// True while the chosen cover is downloading and being saved.
  bool _saving = false;
  /// A message to show in place of results (nothing typed, no internet, download failed).
  String? _error;

  @override
  void initState() {
    super.initState();
    // Start searching straight away with the names we were given.
    _run();
  }

  @override
  void dispose() {
    _artist.dispose();
    _album.dispose();
    _search.close();
    super.dispose();
  }

  /// Runs the search with whatever's in the Artist and Album boxes.
  Future<void> _run() async {
    final artist = _artist.text.trim();
    final album = _album.text.trim();
    if (artist.isEmpty && album.isEmpty) {
      setState(() => _error = 'Enter an artist or album name to search.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _search.search(artist: artist, album: album, title: widget.title);
      // The dialog may have been closed while we were waiting on the internet.
      if (!mounted) return;
      setState(() {
        _results = r;
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

  /// Downloads the full-size cover, stores a copy in the app's cover folder and closes the
  /// dialog with that file's path.
  Future<void> _choose(CoverCandidate c) async {
    final lib = context.read<LibraryModel>();
    setState(() => _saving = true);
    try {
      final bytes = await _search.download(c);
      final path = await lib.importCoverBytes(bytes);
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Couldn\'t download that cover. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    // Pick what the middle of the dialog shows: spinner, error, "nothing found", or the grid.
    Widget body;
    if (_loading || _saving) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_saving ? 'Saving cover…' : 'Searching…', style: const TextStyle(color: AppColors.textDim)),
        ]),
      );
    } else if (_error != null) {
      body = Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)));
    } else if (results == null || results.isEmpty) {
      body = const Center(
        child: Text('No covers found. Try adjusting the artist or album name.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
      );
    } else {
      // A grid of square covers with the release title and artist/year under each.
      body = GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          childAspectRatio: 0.72,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final c = results[i];
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _choose(c),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(c.thumbnail, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 4),
              Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text([c.artist, if (c.year != null) c.year!].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          );
        },
      );
    }

    // The dialog frame: title + close, the two search boxes, the results, and a credit line.
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('Find cover online', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _artist,
                  decoration: const InputDecoration(labelText: 'Artist', isDense: true),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _album,
                  decoration: const InputDecoration(labelText: 'Album', isDense: true),
                  onSubmitted: (_) => _run(),
                ),
              ),
              IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _loading ? null : _run),
            ]),
            const SizedBox(height: 12),
            Expanded(child: body),
            const SizedBox(height: 8),
            const Text(
              'Tap a cover to use it. Covers from Cover Art Archive, album info from MusicBrainz.',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ]),
        ),
      ),
    );
  }
}
