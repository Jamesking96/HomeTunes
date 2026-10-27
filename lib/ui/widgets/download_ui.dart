// The download parts of the menus (0.2.3, step 3 of the Servers & Downloads plan), shared by the
// song, album, audiobook, playlist, video, collection and season menus and the selection bars:
// Download… (asks which copy: the original file or a smaller one, each time, as the user chose),
// Stop downloading, Remove download(s), Keep offline / Stop keeping offline, and Make it mine…
// (copies a downloaded file into one of your own folders). Everything goes through DownloadsModel
// (state/downloads_model.dart); when there isn't one (some tests), no options are offered.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/download.dart';
import '../../state/downloads_model.dart';
import '../theme.dart';

/// The downloads, or null where the app doesn't provide them.
DownloadsModel? downloadsOf(BuildContext context, {bool listen = false}) =>
    Provider.of<DownloadsModel?>(context, listen: listen);

/// One download item in a menu.
class DownloadOption {
  final String key;
  final IconData icon;
  final String label;
  final Future<void> Function() run;
  const DownloadOption(this.key, this.icon, this.label, this.run);
}

/// What a menu offers for [items] (only server ones count). [keep]: the thing they're in, when
/// it can be kept offline as a whole (an album, a playlist, Liked Songs, a book, a collection, a
/// season).
List<DownloadOption> downloadOptions(
  BuildContext context,
  List<DownloadItem> items, {
  ({KeepKind kind, String key, String label})? keep,
}) {
  final dl = downloadsOf(context);
  final server = [for (final it in items) if (isServerDownloadId(it.id)) it];
  if (dl == null || server.isEmpty) return const [];
  final video = server.first.kind == DownloadKind.video;
  final notYet = [for (final it in server) if (!dl.isDownloaded(it.id) && !dl.isPending(it.id)) it];
  final pending = [for (final it in server) if (dl.isPending(it.id)) it.id];
  final done = [for (final it in server) if (dl.isDownloaded(it.id)) it.id];
  final kept = keep != null && dl.isKept(keep.kind, keep.key);
  final n = server.length;
  final mine = n == 1 && done.length == 1 ? dl.entryOf(done.first) : null;
  return [
    if (notYet.isNotEmpty)
      DownloadOption('download', Icons.download_outlined,
          notYet.length == 1 && n == 1 ? 'Download…' : (notYet.length == n ? 'Download all $n…' : 'Download the other ${notYet.length}…'),
          () => startDownload(context, notYet)),
    if (pending.isNotEmpty)
      DownloadOption('download-stop', Icons.cancel_outlined,
          pending.length == 1 ? 'Stop downloading' : 'Stop downloading ${pending.length}', () => dl.remove(pending)),
    if (done.isNotEmpty)
      DownloadOption('download-remove', Icons.delete_outline,
          done.length == 1 ? 'Remove download' : 'Remove ${done.length} downloads', () => removeDownloads(context, done)),
    if (keep != null)
      DownloadOption(kept ? 'keep-off' : 'keep-on', kept ? Icons.cloud_off_outlined : Icons.offline_pin_outlined,
          kept ? 'Stop keeping offline' : 'Keep offline…', () => toggleKeepOffline(context, keep, video: video)),
    if (mine != null && dl.foldersFor(mine).isNotEmpty)
      DownloadOption('make-mine', Icons.drive_file_move_outline, 'Make it mine…', () => makeItMine(context, mine)),
  ];
}

/// Whether [id] is something from a server (only those can be downloaded).
bool isServerDownloadId(String id) => id.startsWith('server:') || id.startsWith('jf:');

/// The options as popup menu items whose value is the action (song rows).
List<PopupMenuEntry<VoidCallback>> downloadMenuItems(BuildContext context, List<DownloadItem> items,
    {({KeepKind kind, String key, String label})? keep}) {
  final opts = downloadOptions(context, items, keep: keep);
  if (opts.isEmpty) return const [];
  return [
    const PopupMenuDivider(),
    for (final o in opts)
      PopupMenuItem<VoidCallback>(
        key: ValueKey('menu-${o.key}'),
        value: () => o.run(),
        child: Row(children: [Icon(o.icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(o.label))]),
      ),
  ];
}

/// A ⋮ button with just the download options (Liked Songs' app bar). Hidden when there are none.
class DownloadMenuButton extends StatelessWidget {
  final List<DownloadItem> Function() items;
  final ({KeepKind kind, String key, String label})? keep;
  const DownloadMenuButton({super.key, required this.items, this.keep});

  @override
  Widget build(BuildContext context) {
    downloadsOf(context, listen: true); // redraws as downloads change
    final opts = downloadOptions(context, items(), keep: keep);
    if (opts.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<DownloadOption>(
      key: const ValueKey('download-menu'),
      tooltip: 'Downloads',
      icon: const Icon(Icons.download_for_offline_outlined),
      onSelected: (o) => o.run(),
      itemBuilder: (_) => [
        for (final o in opts)
          PopupMenuItem(
            key: ValueKey('menu-${o.key}'),
            value: o,
            child: Row(children: [Icon(o.icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(o.label))]),
          ),
      ],
    );
  }
}

/// Asks which copy, then downloads [items]. Says how many in a notice.
Future<void> startDownload(BuildContext context, List<DownloadItem> items) async {
  final dl = downloadsOf(context);
  if (dl == null || items.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final video = items.first.kind == DownloadKind.video;
  final bytes = items.fold<int>(0, (s, it) => s + (it.size ?? 0));
  final length = items.fold<Duration>(Duration.zero, (s, it) => s + it.length);
  final q = await askDownloadQuality(context,
      video: video,
      what: items.length == 1 ? '"${items.first.title}"' : '${items.length} ${video ? 'videos' : 'songs'}',
      originalBytes: bytes > 0 ? bytes : null,
      length: length);
  if (q == null) return;
  final added = dl.download(items, q);
  messenger?.showSnackBar(SnackBar(
    content: Text(added == 0
        ? 'Already downloaded'
        : added == 1
            ? 'Downloading "${items.first.title}"'
            : 'Downloading $added ${video ? 'videos' : 'songs'}'),
  ));
}

/// Removes downloads [ids], asking first when it's more than one.
Future<void> removeDownloads(BuildContext context, List<String> ids) async {
  final dl = downloadsOf(context);
  if (dl == null || ids.isEmpty) return;
  if (ids.length > 1) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${ids.length} downloads?'),
        content: const Text('They stay in your library and stream from the server again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
  }
  await dl.remove(ids);
}

/// Keep offline on (asks which copy first), or off (asks whether to keep what it downloaded).
Future<void> toggleKeepOffline(BuildContext context, ({KeepKind kind, String key, String label}) keep,
    {required bool video}) async {
  final dl = downloadsOf(context);
  if (dl == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (dl.isKept(keep.kind, keep.key)) {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop keeping "${keep.label}" offline?'),
        content: const Text('New things in it won\'t download by themselves any more.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              key: const ValueKey('keep-off-remove'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Also remove its downloads')),
          FilledButton(
              key: const ValueKey('keep-off-keep'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep its downloads')),
        ],
      ),
    );
    if (remove == null) return;
    await dl.setKept(keep.kind, keep.key, keep.label, false, removeDownloads: remove);
    return;
  }
  if (!context.mounted) return;
  final q = await askDownloadQuality(context, video: video, what: '"${keep.label}"', keeping: true);
  if (q == null) return;
  await dl.setKept(keep.kind, keep.key, keep.label, true, quality: q);
  messenger?.showSnackBar(SnackBar(content: Text('"${keep.label}" is kept offline')));
}

/// Which copy to download: the original file, or a smaller one the server converts. Null when
/// cancelled. [keeping]: for Keep offline (said in the text).
Future<DownloadQuality?> askDownloadQuality(
  BuildContext context, {
  required bool video,
  required String what,
  int? originalBytes,
  Duration length = Duration.zero,
  bool keeping = false,
}) =>
    showDialog<DownloadQuality>(
      context: context,
      builder: (ctx) => _QualityDialog(video: video, what: what, originalBytes: originalBytes, length: length, keeping: keeping),
    );

/// The copies offered: the original file, then the smaller ones (shared with the TV's panel).
List<DownloadQuality> downloadQualityChoices({required bool video}) => [
      DownloadQuality.original(video: video),
      for (final h in video ? DownloadQuality.videoHeights : DownloadQuality.audioBitrates)
        video ? DownloadQuality.videoHeight(h) : DownloadQuality.audioBitrate(h),
    ];

/// "Original file", "Smaller copy, 720p", "Smaller copy, 192 kbit/s MP3".
String downloadQualityLabel(DownloadQuality q, {required bool video}) => q.isOriginal
    ? 'Original file'
    : video
        ? 'Smaller copy, ${q.limit}p'
        : 'Smaller copy, ${q.limit} kbit/s MP3';

/// About how much space [q] takes for things [length] long ("about 1.2 GB"), or null when
/// there's nothing to go on.
String? downloadSizeEstimate(DownloadQuality q, {Duration length = Duration.zero, int? originalBytes}) {
  if (length <= Duration.zero && (q.isOriginal ? originalBytes == null : true)) return null;
  final b = q.estimate(length, originalBytes: originalBytes);
  return b <= 0 ? null : '${q.isOriginal && originalBytes != null ? '' : 'about '}${fileSizeText(b)}';
}

class _QualityDialog extends StatefulWidget {
  final bool video, keeping;
  final String what;
  final int? originalBytes;
  final Duration length;
  const _QualityDialog({required this.video, required this.what, this.originalBytes, required this.length, required this.keeping});

  @override
  State<_QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends State<_QualityDialog> {
  late DownloadQuality _q = DownloadQuality.original(video: widget.video);

  String? _size(DownloadQuality q) =>
      downloadSizeEstimate(q, length: widget.length, originalBytes: widget.originalBytes);

  @override
  Widget build(BuildContext context) {
    final options = downloadQualityChoices(video: widget.video);
    String label(DownloadQuality q) => downloadQualityLabel(q, video: widget.video);
    return AlertDialog(
      title: Text(widget.keeping ? 'Keep ${widget.what} offline' : 'Download ${widget.what}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            widget.keeping
                ? 'Everything in it downloads now, and anything added later downloads by itself.'
                : 'The original is exactly what\'s on the server. A smaller copy is converted by the server '
                    'as it downloads, and takes less space.',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
          const SizedBox(height: 8),
          RadioGroup<DownloadQuality>(
            groupValue: _q,
            onChanged: (v) => setState(() => _q = v ?? _q),
            child: Column(children: [
              for (final q in options)
                RadioListTile<DownloadQuality>(
                  key: ValueKey('quality-${q.code}'),
                  value: q,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(label(q)),
                  subtitle: _size(q) == null ? null : Text(_size(q)!),
                ),
            ]),
          ),
          if (Platform.isAndroid && (downloadsOf(context)?.wifiOnly ?? false))
            Text('Downloads over Wi-Fi only (Settings › Servers › Downloads).',
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('quality-ok'),
          onPressed: () => Navigator.pop(context, _q),
          child: Text(widget.keeping ? 'Keep offline' : 'Download'),
        ),
      ],
    );
  }
}

/// Make it mine: copies download [e] into one of your folders (asking which when there are
/// several), so it's one of your own files from then on.
Future<void> makeItMine(BuildContext context, DownloadEntry e) async {
  final dl = downloadsOf(context);
  if (dl == null) return;
  final folders = dl.foldersFor(e);
  if (folders.isEmpty) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final kind = e.kind == DownloadKind.video ? 'video' : (e.book ? 'audiobook' : 'music');
  final folder = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Make "${e.title}" yours'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'A copy goes into your $kind folder and becomes one of your own files. The download is '
            'removed; the server still has it.',
            style: TextStyle(fontSize: 13, color: AppColors.textDim),
          ),
        ),
        for (final f in folders)
          SimpleDialogOption(
            key: ValueKey('make-mine:$f'),
            onPressed: () => Navigator.pop(ctx, f),
            child: Row(children: [const Icon(Icons.folder_outlined, size: 20), const SizedBox(width: 12), Expanded(child: Text(f))]),
          ),
      ],
    ),
  );
  if (folder == null) return;
  try {
    final to = await dl.makeItMine(e.id, folder);
    messenger?.showSnackBar(SnackBar(content: Text('Copied to $to')));
  } on FileSystemException catch (x) {
    messenger?.showSnackBar(SnackBar(
        content: Text('Couldn\'t copy it there${Platform.isAndroid ? ' (Android may not let HomeTunes write to that folder)' : ''}: ${x.message}')));
  }
}
