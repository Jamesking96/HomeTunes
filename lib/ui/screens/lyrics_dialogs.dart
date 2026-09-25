import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lyrics.dart';
import '../../models/track.dart';
import '../../services/lrclib_client.dart';
import '../../state/lyrics_model.dart';
import '../theme.dart';
import '../widgets/lyrics_view.dart';

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
    builder: (_) => ChangeNotifierProvider.value(value: model, child: _LrclibDialog(track: track)),
  );
  if (text == null) return;
  await model.setYours(track, text);
  messenger?.showSnackBar(SnackBar(content: Text('Lyrics saved for "${track.title}"')));
}

class _LrclibDialog extends StatefulWidget {
  final Track track;
  const _LrclibDialog({required this.track});

  @override
  State<_LrclibDialog> createState() => _LrclibDialogState();
}

class _LrclibDialogState extends State<_LrclibDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(text: widget.track.artist);
  List<LrclibMatch>? _results;
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
      final r = await context.read<LyricsModel>().search(widget.track, title: title, artist: _artist.text.trim());
      if (!mounted) return;
      setState(() {
        _results = [for (final m in r) if (m.hasLyrics || m.instrumental) m];
        _loading = false;
      });
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
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)));
    } else if (preview != null) {
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
            onTap: m.hasLyrics ? () => setState(() => _preview = m) : null,
          );
        },
      );
    }

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
  final model = context.read<LyricsModel>();
  final current = await model.lyricsFor(track, online: false);
  if (!context.mounted) return;
  final result = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _EditLyricsDialog(track: track, initial: current?.text ?? ''),
  );
  if (result == null || result == (current?.text ?? '')) return;
  if (result.trim().isEmpty) {
    await model.removeYours(track);
  } else {
    await model.setYours(track, result);
  }
}

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
