// The lyrics dialogs, all opened from a song's ⋮ menu or the lyrics view:
//  - showLyricsDialog: shows a song's lyrics in a pop-up (the same LyricsView as Now Playing).
//  - findLyricsOnline: "Find lyrics on LRCLIB…" – search, preview a result, then "Use these
//    lyrics" saves it as the user's own lyrics for that song.
//  - editLyrics: "Edit lyrics" – type or paste plain or timed (LRC) lyrics; clearing the box
//    removes the user's lyrics so the file's / online ones show again.
// Where lyrics come from and how they're stored is LyricsModel's job (state/lyrics_model.dart);
// the user's own lyrics are kept as the `lyrics` field of the song's TrackEdit.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lyrics.dart';
import '../../models/track.dart';
import '../../services/lrclib_client.dart';
import '../../state/lyrics_model.dart';
import '../theme.dart';
import '../widgets/lyrics_view.dart';

/// Formats a length as "m:ss" for the result list.
String _mmss(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Shows a song's lyrics in a dialog (from the song's ⋮ menu).
Future<void> showLyricsDialog(BuildContext context, Track track) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textDim)),
                ]),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
          Expanded(child: LyricsView(track: track, large: false)),
        ]),
      ),
    ),
  );
}

/// Searches LRCLIB for a song's lyrics and lets the user pick a result
/// (after seeing it). The pick becomes the song's lyrics.
Future<void> findLyricsOnline(BuildContext context, Track track) async {
  final model = context.read<LyricsModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final text = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    // The dialog opens on the root navigator, so hand it the model explicitly.
    builder: (_) => ChangeNotifierProvider.value(value: model, child: _LrclibDialog(track: track)),
  );
  // Null means the dialog was closed without picking anything.
  if (text == null) return;
  await model.setYours(track, text);
  messenger?.showSnackBar(SnackBar(content: Text('Lyrics saved for "${track.title}"')));
}

/// The LRCLIB search dialog: a list of results, and a preview of the one tapped.
class _LrclibDialog extends StatefulWidget {
  final Track track;
  const _LrclibDialog({required this.track});

  @override
  State<_LrclibDialog> createState() => _LrclibDialogState();
}

class _LrclibDialogState extends State<_LrclibDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(text: widget.track.artist);
  /// The search results, or null before the first search has finished.
  List<LrclibMatch>? _results;
  /// The result being previewed, or null while showing the list.
  LrclibMatch? _preview;
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
    super.dispose();
  }

  Future<void> _run() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter the song\'s title to search.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      // LyricsModel.search tries title + artist first, then a looser text search.
      final r = await context.read<LyricsModel>().search(widget.track, title: title, artist: _artist.text.trim());
      if (!mounted) return;
      // Drop results with nothing to use (no lyrics and not marked instrumental).
      setState(() {
        _results = [for (final m in r) if (m.hasLyrics || m.instrumental) m];
        _loading = false;
      });
    // The LRCLIB client turns network problems into an LrclibException with a
    // friendly message.
    } on LrclibException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final preview = _preview;
    Widget body;
    // Pick what the middle shows: spinner, error, a preview of one result,
    // "nothing found", or the list.
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)));
    } else if (preview != null) {
      // Preview: show the lines (with their times, if timed) and a way back to the list.
      final lyrics = Lyrics(preview.bestLyrics ?? '', LyricsSource.lrclib);
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextButton.icon(
          onPressed: () => setState(() => _preview = null),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All results'),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final l in lyrics.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(TextSpan(children: [
                      if (l.time != null)
                        TextSpan(
                          // Just "mm:ss" of the time, to keep the preview tidy.
                          text: '${formatLrcTime(l.time!).substring(0, 5)}  ',
                          style: const TextStyle(color: AppColors.textDim, fontFeatures: [FontFeature.tabularFigures()]),
                        ),
                      TextSpan(text: l.text),
                    ])),
                  ),
              ],
            ),
          ),
        ),
      ]);
    } else if (_results == null || _results!.isEmpty) {
      body = const Center(
        child: Text('LRCLIB has no lyrics for that. Try changing the title or artist.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
      );
    } else {
      body = ListView.builder(
        itemCount: _results!.length,
        itemBuilder: (_, i) {
          final m = _results![i];
          // "Same length" when the result is within about 3 seconds of the song's
          // length: a good sign it's the same recording.
          final close = t.hasDuration && LrclibClient.closeLength(m.duration, t.duration);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text('${m.title} · ${m.artist}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [if (m.album.isNotEmpty) m.album, _mmss(m.duration)].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Wrap(spacing: 6, children: [
              if (close) const _Chip('Same length'),
              _Chip(m.instrumental && !m.hasLyrics ? 'Instrumental' : (m.timed ? 'Timed' : 'Plain')),
            ]),
            // Instrumental-only results can't be previewed (there's nothing to show).
            onTap: m.hasLyrics ? () => setState(() => _preview = m) : null,
          );
        },
      );
    }

    // The dialog frame: title + close, the song being searched for, search boxes (hidden while
    // previewing), the results, and a note on what's sent to LRCLIB.
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('Find lyrics on LRCLIB', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            Text('${t.title} · ${t.artist}${t.hasDuration ? ' · ${_mmss(t.duration)}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 8),
            if (preview == null)
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title', isDense: true),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _artist,
                    decoration: const InputDecoration(labelText: 'Artist', isDense: true),
                    onSubmitted: (_) => _run(),
                  ),
                ),
                IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _loading ? null : _run),
              ]),
            const SizedBox(height: 12),
            Expanded(child: body),
            const SizedBox(height: 8),
            Row(children: [
              const Expanded(
                child: Text('Lyrics from LRCLIB (lrclib.net). Only the title, artist, album and length are sent.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              ),
              // While previewing: keep the old lyrics, or use these (the text goes back
              // to findLyricsOnline, which saves it).
              if (preview != null) ...[
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep what I have')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, preview.bestLyrics),
                  child: const Text('Use these lyrics'),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A small rounded label on a search result ("Timed", "Same length"…).
class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
      );
}

/// Type or paste a song's lyrics (plain, or timed LRC).
Future<void> editLyrics(BuildContext context, Track track) async {
  // Start the box with the lyrics the song shows now (without searching online).
  final model = context.read<LyricsModel>();
  final current = await model.lyricsFor(track, online: false);
  if (!context.mounted) return;
  final result = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _EditLyricsDialog(track: track, initial: current?.text ?? ''),
  );
  // Cancelled, or saved without changing anything: nothing to do.
  if (result == null || result == (current?.text ?? '')) return;
  if (result.trim().isEmpty) {
    await model.removeYours(track);
  } else {
    await model.setYours(track, result);
  }
}

/// The "Edit lyrics" dialog: one big text box. Returns the text when Save is pressed.
class _EditLyricsDialog extends StatefulWidget {
  final Track track;
  final String initial;
  const _EditLyricsDialog({required this.track, required this.initial});

  @override
  State<_EditLyricsDialog> createState() => _EditLyricsDialogState();
}

class _EditLyricsDialogState extends State<_EditLyricsDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit lyrics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text('${widget.track.title} · ${widget.track.artist}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(height: 1.4),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Type or paste the lyrics here.\n\n'
                      'For lyrics that follow the song, start each line with its time, like [01:23.45].',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved in HomeTunes, like other edits. Settings › Your edits can also put them into '
              'MP3, FLAC and M4A files. Clear the box and save to remove your lyrics.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save')),
            ]),
          ]),
        ),
      ),
    );
  }
}
