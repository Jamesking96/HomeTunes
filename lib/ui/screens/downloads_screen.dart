// The Downloads page (0.2.3, step 3 of the Servers & Downloads plan): what's downloading or
// waiting (with pause, carry on, try again and stop), what's kept offline (with Stop keeping
// offline), and everything downloaded (play it, Make it mine…, remove it), plus how much space
// they take against the limit. Opened from the sidebar, from Settings › Servers › Downloads and
// from the Library tab. Everything comes from DownloadsModel (state/downloads_model.dart).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/download.dart';
import '../../models/track.dart';
import '../../state/downloads_model.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show EmptyState;
import '../widgets/download_ui.dart';

/// Which downloads the page lists.
enum DownloadsView { all, videos, music }

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  DownloadsView _view = DownloadsView.all;

  bool _shows(DownloadEntry e) => switch (_view) {
        DownloadsView.all => true,
        DownloadsView.videos => e.kind == DownloadKind.video,
        DownloadsView.music => e.kind == DownloadKind.song,
      };

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context, listen: true);
    if (dl == null) {
      return Scaffold(appBar: AppBar(title: const Text('Downloads')), body: const SizedBox.shrink());
    }
    final waiting = [for (final e in dl.waiting) if (_shows(e)) e];
    final done = [for (final e in dl.done) if (_shows(e)) e];
    final temporary = [for (final e in dl.temporaries) if (_shows(e)) e];
    final kept = [
      for (final k in dl.kept)
        if (_view == DownloadsView.all ||
            (_view == DownloadsView.videos) == (k.kind == KeepKind.collection || k.kind == KeepKind.season))
          k,
    ];
    final anyRunning = dl.waiting.any((e) => e.state == DownloadState.running || e.state == DownloadState.queued);
    final anyPaused = dl.waiting.any((e) => e.state == DownloadState.paused);
    final limit = dl.limitBytes;
    final used = dl.usedBytes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (anyRunning)
            IconButton(key: const ValueKey('downloads-pause-all'), tooltip: 'Pause all', icon: const Icon(Icons.pause), onPressed: dl.pauseAll),
          if (anyPaused)
            IconButton(
                key: const ValueKey('downloads-resume-all'), tooltip: 'Carry on with all', icon: const Icon(Icons.play_arrow), onPressed: dl.resumeAll),
          // The queue: everything on its way, in the order it'll download (27 Oct).
          IconButton(
            key: const ValueKey('downloads-queue'),
            tooltip: 'Download queue',
            icon: Badge(
              isLabelVisible: dl.queue.isNotEmpty,
              label: Text('${dl.queue.length}'),
              child: const Icon(Icons.queue_outlined),
            ),
            onPressed: () => context.read<AppNav>().openDownloadQueue(),
          ),
          IconButton(
            key: const ValueKey('downloads-settings'),
            tooltip: 'Download settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.read<AppNav>().openSettings('server', setting: 'downloads-folder'),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('downloads-menu'),
            onSelected: (v) async {
              if (v == 'remove-all') await _removeAll(context, dl);
              if (v == 'help' && context.mounted) await showDownloadHelp(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(key: ValueKey('downloads-help-menu'), value: 'help', child: Text('Download or Keep offline?')),
              if (dl.entries.isNotEmpty)
                const PopupMenuItem(key: ValueKey('downloads-remove-all'), value: 'remove-all', child: Text('Remove all downloads…')),
            ],
          ),
        ],
      ),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                limit == null ? '${fileSizeText(used)} used' : '${fileSizeText(used)} of ${fileSizeText(limit)} used',
                key: const ValueKey('downloads-space'),
                style: TextStyle(color: AppColors.textDim),
              ),
              if (limit != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: limit == 0 ? 1 : (used / limit).clamp(0.0, 1.0), minHeight: 4),
              ],
              if (dl.status != null) ...[
                const SizedBox(height: 6),
                Text(dl.status!, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ],
              const SizedBox(height: 8),
              SegmentedButton<DownloadsView>(
                segments: const [
                  ButtonSegment(value: DownloadsView.all, label: Text('All')),
                  ButtonSegment(value: DownloadsView.videos, label: Text('Videos'), icon: Icon(Icons.movie_outlined)),
                  ButtonSegment(value: DownloadsView.music, label: Text('Music & books'), icon: Icon(Icons.music_note_outlined)),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
            ]),
          ),
        ),
        if (waiting.isEmpty && done.isEmpty && kept.isEmpty && temporary.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.download_outlined,
              title: 'Nothing downloaded yet',
              message: 'Choose Download… in the menu of anything streamed from a server, '
                  'and it plays from here even when the server is off.',
            ),
          ),
        if (waiting.isNotEmpty) ...[
          _heading('Downloading (${waiting.length})'),
          SliverList.builder(itemCount: waiting.length, itemBuilder: (_, i) => _Row(entry: waiting[i])),
        ],
        if (kept.isNotEmpty) ...[
          _heading('Kept offline'),
          SliverList.builder(itemCount: kept.length, itemBuilder: (_, i) => _KeptRow(keep: kept[i])),
        ],
        if (done.isNotEmpty) ...[
          _heading('Downloaded (${done.length})'),
          SliverList.builder(itemCount: done.length, itemBuilder: (_, i) => _Row(entry: done[i])),
        ],
        // Saved while streaming (0.2.4): cleared away by themselves, unless kept.
        if (temporary.isNotEmpty) ...[
          _heading('Temporary copies (${temporary.length}) · ${fileSizeText(dl.tempUsedBytes)} of ${fileSizeText(dl.tempLimitBytes)}'),
          SliverList.builder(itemCount: temporary.length, itemBuilder: (_, i) => _Row(entry: temporary[i])),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }

  static Widget _heading(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );

  static Future<void> _removeAll(BuildContext context, DownloadsModel dl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: const Text('Everything stays in your library and streams from the server again. '
            'What\'s kept offline downloads again unless you stop keeping it offline.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('downloads-remove-all-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove all')),
        ],
      ),
    );
    if (ok == true) await dl.removeAll();
  }
}

/// One download: what it is, where it's got to, and what can be done with it.
class _Row extends StatelessWidget {
  final DownloadEntry entry;
  const _Row({required this.entry, this.position});

  /// Its place in the download queue (the queue page), shown instead of its kind's icon.
  final int? position;

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context)!;
    final e = entry;
    final video = e.kind == DownloadKind.video;
    final icon = video ? Icons.movie_outlined : (e.book ? Icons.menu_book_outlined : Icons.music_note_outlined);
    // On the queue page every waiting one shows its bar (grey until it starts).
    final running = e.state == DownloadState.running || (position != null && !e.isDone && e.state != DownloadState.failed);
    final status = dl.statusOf(e);
    final problem = e.state == DownloadState.failed || e.state == DownloadState.noRoom;
    return ListTile(
      key: ValueKey('download:${e.id}'),
      leading: position == null
          ? Icon(icon)
          : CircleAvatar(
              key: ValueKey('queue-position:${e.id}'),
              radius: 14,
              backgroundColor: e.state == DownloadState.running ? Theme.of(context).colorScheme.primary : AppColors.surfaceHigh,
              child: Text('$position', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (e.subtitle.isNotEmpty) Text(e.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: problem ? Theme.of(context).colorScheme.error : AppColors.textDim)),
        if (running)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(
              value: e.expected != null && e.expected! > 0 ? e.progress.clamp(0.0, 1.0) : (e.state == DownloadState.running ? null : 0),
              minHeight: 3,
              color: e.state == DownloadState.running ? null : AppColors.textDim,
            ),
          ),
      ]),
      onTap: e.isDone ? () => _play(context, e) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (e.state == DownloadState.running || e.state == DownloadState.queued)
          IconButton(key: ValueKey('download-pause:${e.id}'), tooltip: 'Pause', icon: const Icon(Icons.pause), onPressed: () => dl.pause(e.id)),
        if (e.state == DownloadState.paused)
          IconButton(
              key: ValueKey('download-resume:${e.id}'), tooltip: 'Carry on', icon: const Icon(Icons.play_arrow), onPressed: () => dl.resume(e.id)),
        if (problem)
          IconButton(key: ValueKey('download-retry:${e.id}'), tooltip: 'Try again', icon: const Icon(Icons.refresh), onPressed: () => dl.retry(e.id)),
        if (e.isTemporary)
          IconButton(
            key: ValueKey('download-keep:${e.id}'),
            tooltip: 'Keep this copy',
            icon: const Icon(Icons.push_pin_outlined),
            onPressed: () => dl.keepCopies([e.id]),
          ),
        if (e.isDone && dl.foldersFor(e).isNotEmpty)
          IconButton(
            key: ValueKey('download-mine:${e.id}'),
            tooltip: 'Make it mine',
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: () => makeItMine(context, e),
          ),
        IconButton(
          key: ValueKey('download-remove:${e.id}'),
          tooltip: e.isDone ? (e.isTemporary ? 'Remove temporary copy' : 'Remove download') : 'Stop downloading',
          icon: Icon(e.isDone ? Icons.delete_outline : Icons.close),
          onPressed: () => dl.remove([e.id]),
        ),
      ]),
    );
  }

  static void _play(BuildContext context, DownloadEntry e) {
    if (e.kind == DownloadKind.video) {
      final v = context.read<VideoLibraryModel>().byId(e.id);
      if (v != null) context.read<AppNav>().openVideo(v);
      return;
    }
    final t = context.read<LibraryModel>().byId(e.id);
    if (t != null) context.read<PlayerModel>().playTracks(<Track>[t], label: 'Downloads');
  }
}

/// Something kept offline (an album, a playlist, a series…).
class _KeptRow extends StatelessWidget {
  final KeepOffline keep;
  const _KeptRow({required this.keep});

  @override
  Widget build(BuildContext context) {
    final video = keep.kind == KeepKind.collection || keep.kind == KeepKind.season;
    return ListTile(
      key: ValueKey('kept:${keep.id}'),
      leading: const Icon(Icons.offline_pin_outlined),
      title: Text(keep.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${keep.kind.label} · ${keep.quality.label}', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
      trailing: IconButton(
        key: ValueKey('kept-off:${keep.id}'),
        tooltip: 'Stop keeping offline',
        icon: const Icon(Icons.cloud_off_outlined),
        onPressed: () => toggleKeepOffline(context, (kind: keep.kind, key: keep.key, label: keep.label), video: video),
      ),
    );
  }
}

/// The download queue (27 Oct, the user: "a new button near the downloading settings that takes
/// you to a list of all medias being downloaded in a queue format"): everything on its way,
/// numbered in the order it'll download (what's downloading now first; two download at once),
/// each with its bar, and pause, carry on, try again and stop. Opened from Settings › Servers ›
/// Downloads › Download queue and the Downloads page's queue button.
class DownloadQueueScreen extends StatelessWidget {
  const DownloadQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context, listen: true);
    if (dl == null) {
      return Scaffold(appBar: AppBar(title: const Text('Download queue')), body: const SizedBox.shrink());
    }
    final queue = dl.queue;
    final running = queue.where((e) => e.state == DownloadState.running).length;
    final left = queue.fold<int>(0, (s, e) => s + math.max(0, (e.expected ?? 0) - e.bytes));
    final anyGoing = queue.any((e) => e.state == DownloadState.running || e.state == DownloadState.queued);
    final anyPaused = queue.any((e) => e.state == DownloadState.paused);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Download queue'),
        actions: [
          if (anyGoing)
            IconButton(key: const ValueKey('queue-pause-all'), tooltip: 'Pause all', icon: const Icon(Icons.pause), onPressed: dl.pauseAll),
          if (anyPaused)
            IconButton(
                key: const ValueKey('queue-resume-all'), tooltip: 'Carry on with all', icon: const Icon(Icons.play_arrow), onPressed: dl.resumeAll),
          IconButton(
            key: const ValueKey('queue-downloads'),
            tooltip: 'All downloads',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => context.read<AppNav>().openDownloads(),
          ),
        ],
      ),
      body: queue.isEmpty
          ? const EmptyState(
              icon: Icons.download_done_outlined,
              title: 'Nothing waiting to download',
              message: 'Anything you download, keep offline or save while streaming lines up here until it\'s done.',
            )
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  [
                    '${queue.length} in the queue',
                    if (running > 0) '$running downloading now',
                    if (left > 0) 'about ${fileSizeText(left)} to go',
                    if (Platform.isAndroid && dl.wifiOnly && dl.onWifi == false) 'waiting for Wi-Fi',
                  ].join(' · '),
                  key: const ValueKey('queue-summary'),
                  style: TextStyle(color: AppColors.textDim),
                ),
              ),
              for (var i = 0; i < queue.length; i++) _Row(entry: queue[i], position: i + 1),
              const SizedBox(height: 24),
            ]),
    );
  }
}
