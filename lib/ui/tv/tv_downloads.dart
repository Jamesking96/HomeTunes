// Downloads on the TV (0.2.3): the same choices as the menus elsewhere (download_ui.dart), laid
// out for the remote in the options panel, and a TV Downloads page.
//  * Download › and Keep offline › open a second panel to pick the copy (the original file, or a
//    smaller one the server makes as it downloads), with about how much space each takes.
//  * Stop keeping offline › asks whether to keep what it downloaded; Remove n downloads › asks
//    first; Make it mine › picks one of your folders.
//  * The Downloads page (TvDownloadsPage, opened by AppNav.openDownloads in TV mode, from Music's
//    Downloads tile and Settings › Servers › Downloads): what's downloading, what's kept offline
//    and what's downloaded. OK plays a download (or opens its options while it's still coming);
//    holding OK gives Pause / Carry on / Try again, Make it mine and Remove.
import 'dart:io';

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
import '../widgets/download_ui.dart';
import 'tv_browse.dart';
import 'tv_detail.dart';
import 'tv_menus.dart' show tvNotice, tvConfirm;
import 'tv_options.dart';
import 'tv_widgets.dart';

typedef TvKeep = ({KeepKind kind, String key, String label});

/// The download choices for [items] in a TV options panel (none when nothing is from a server,
/// or the app has no downloads). [keep]: what they're in, when it can be kept offline as a whole.
List<TvOption> tvDownloadOptions(BuildContext context, List<DownloadItem> items, {TvKeep? keep}) {
  final dl = downloadsOf(context);
  if (dl == null) return const [];
  final server = [for (final it in items) if (isServerDownloadId(it.id)) it];
  if (server.isEmpty) return const [];
  final video = server.first.kind == DownloadKind.video;
  final notYet = [for (final it in server) if (!dl.isDownloaded(it.id) && !dl.isPending(it.id)) it];
  final pending = [for (final it in server) if (dl.isPending(it.id)) it.id];
  final done = [for (final it in server) if (dl.isDownloaded(it.id)) it.id];
  final n = server.length;
  final kept = keep != null && dl.isKept(keep.kind, keep.key);
  final mine = n == 1 && done.length == 1 ? dl.entryOf(done.first) : null;
  // Temporary copies (0.2.4), here or still being saved: Keep makes them downloads.
  final temporary = [for (final it in server) if (dl.entryOf(it.id)?.isTemporary ?? false) it.id];
  final allTemporary = done.isNotEmpty && done.every(temporary.contains);
  return [
    if (temporary.isNotEmpty)
      TvOption(temporary.length == 1 ? 'Keep this copy' : 'Keep ${temporary.length} temporary copies', Icons.push_pin_outlined,
          () async {
        await dl.keepCopies(temporary);
        if (context.mounted) tvNotice(context, temporary.length == 1 ? 'Kept: it\'s a download now' : 'Kept: they\'re downloads now');
      }),
    if (notYet.isNotEmpty)
      TvOption(
        notYet.length == 1 && n == 1 ? 'Download' : (notYet.length == n ? 'Download all $n' : 'Download the other ${notYet.length}'),
        Icons.download_outlined,
        opensMore: true,
        () => tvStartDownload(context, notYet),
      ),
    if (pending.isNotEmpty)
      TvOption(pending.length == 1 ? 'Stop downloading' : 'Stop downloading ${pending.length}', Icons.cancel_outlined, () {
        dl.remove(pending);
        tvNotice(context, pending.length == 1 ? 'Download stopped' : 'Stopped ${pending.length} downloads');
      }),
    if (done.length == 1)
      TvOption(allTemporary ? 'Remove temporary copy' : 'Remove download', Icons.delete_outline, () {
        dl.remove(done);
        tvNotice(context, '${allTemporary ? 'Copy' : 'Download'} removed. It streams from the server again');
      })
    else if (done.length > 1)
      TvOption(allTemporary ? 'Remove ${done.length} temporary copies' : 'Remove ${done.length} downloads', Icons.delete_outline,
          opensMore: true, () {
        tvConfirm(context,
            title: allTemporary ? 'Remove ${done.length} temporary copies?' : 'Remove ${done.length} downloads?',
            subtitle: 'They stay in your library and stream from the server again',
            yes: 'Remove them',
            run: () => dl.remove(done));
      }),
    if (keep != null)
      TvOption(kept ? 'Stop keeping offline' : 'Keep offline', kept ? Icons.cloud_off_outlined : Icons.offline_pin_outlined,
          opensMore: true, () => kept ? tvStopKeeping(context, keep) : tvKeepOffline(context, keep, video: video)),
    if (mine != null && dl.foldersFor(mine).isNotEmpty)
      TvOption('Make it mine', Icons.drive_file_move_outline, opensMore: true, () => tvMakeItMine(context, mine)),
  ];
}

/// The panel that asks which copy. [onPicked] gets the choice.
Future<void> _askCopy(
  BuildContext context, {
  required bool video,
  required String title,
  required String subtitle,
  Duration length = Duration.zero,
  int? originalBytes,
  required void Function(DownloadQuality q) onPicked,
}) {
  final dl = downloadsOf(context);
  final wifi = Platform.isAndroid && (dl?.wifiOnly ?? false);
  return showTvOptions(context, title: title, subtitle: subtitle, options: [
    for (final q in downloadQualityChoices(video: video))
      TvOption(
        downloadQualityLabel(q, video: video),
        q.isOriginal ? Icons.high_quality_outlined : Icons.compress,
        subtitle: [
          ?downloadSizeEstimate(q, length: length, originalBytes: originalBytes),
          if (q.isOriginal) 'exactly what\'s on the server',
          if (q.isOriginal && wifi) 'over Wi-Fi',
        ].join(' · '),
        () => onPicked(q),
      ),
  ]);
}

/// Download › : which copy, then download [items].
Future<void> tvStartDownload(BuildContext context, List<DownloadItem> items) {
  final dl = downloadsOf(context);
  if (dl == null || items.isEmpty) return Future.value();
  final video = items.first.kind == DownloadKind.video;
  final bytes = items.fold<int>(0, (s, it) => s + (it.size ?? 0));
  final length = items.fold<Duration>(Duration.zero, (s, it) => s + it.length);
  final what = items.length == 1 ? items.first.title : '${items.length} ${video ? 'videos' : 'songs'}';
  return _askCopy(context,
      video: video,
      title: 'Which copy?',
      subtitle: 'Download $what',
      length: length,
      originalBytes: bytes > 0 ? bytes : null, onPicked: (q) {
    final added = dl.download(items, q);
    tvNotice(
        context,
        added == 0
            ? 'Already downloaded'
            : '${added == 1 ? 'Downloading "${items.first.title}"' : 'Downloading $added ${video ? 'videos' : 'songs'}'}'
                '${Platform.isAndroid && dl.wifiOnly && dl.onWifi == false ? ' when you\'re on Wi-Fi' : ''}');
  });
}

/// Keep offline › : which copy, then keep [keep] offline.
Future<void> tvKeepOffline(BuildContext context, TvKeep keep, {required bool video}) {
  final dl = downloadsOf(context);
  if (dl == null) return Future.value();
  return _askCopy(context, video: video, title: 'Keep "${keep.label}" offline', subtitle: 'Everything in it, and anything added later',
      onPicked: (q) async {
    await dl.setKept(keep.kind, keep.key, keep.label, true, quality: q);
    if (context.mounted) tvNotice(context, '"${keep.label}" is kept offline');
  });
}

/// Stop keeping offline › : keep what it downloaded, or remove it too.
Future<void> tvStopKeeping(BuildContext context, TvKeep keep) {
  final dl = downloadsOf(context);
  if (dl == null) return Future.value();
  return showTvOptions(context, title: 'Stop keeping "${keep.label}" offline?', subtitle: 'New things in it won\'t download by themselves', options: [
    TvOption('Keep its downloads', Icons.download_done, () => dl.setKept(keep.kind, keep.key, keep.label, false)),
    TvOption('Also remove its downloads', Icons.delete_outline,
        () => dl.setKept(keep.kind, keep.key, keep.label, false, removeDownloads: true)),
  ]);
}

/// Make it mine › : which of your folders to copy the download into.
Future<void> tvMakeItMine(BuildContext context, DownloadEntry e) {
  final dl = downloadsOf(context);
  if (dl == null) return Future.value();
  return showTvOptions(context, title: 'Make "${e.title}" yours', subtitle: 'A copy goes into your folder; the download is removed', options: [
    for (final f in dl.foldersFor(e))
      TvOption(f, Icons.folder_outlined, () async {
        try {
          final to = await dl.makeItMine(e.id, f);
          if (context.mounted) tvNotice(context, 'Copied to $to');
        } on FileSystemException catch (x) {
          if (context.mounted) tvNotice(context, 'Couldn\'t copy it there: ${x.message}');
        }
      }),
  ]);
}

// ---- The Downloads page ----

/// Music › Playlists' Downloads tile, beside Liked Songs: opens the Downloads page.
TvTile tvDownloadsTile(BuildContext context, {FocusNode? node, double width = 124}) {
  final dl = downloadsOf(context)!;
  final nav = context.read<AppNav>();
  return TvTile(
    key: const ValueKey('tv-downloads'),
    focusNode: node,
    width: width,
    picture: TvColourPicture(colour: AppColors.accent, icon: Icons.download_for_offline),
    title: 'Downloads',
    subtitle: dl.waiting.isEmpty ? '${dl.done.length} downloaded' : '${dl.waiting.length} downloading',
    onPressed: nav.openDownloads,
    onHold: nav.openDownloads,
  );
}

class TvDownloadsPage extends StatelessWidget {
  /// The download queue alone (27 Oct): everything on its way, numbered in the order it'll go.
  final bool queueOnly;
  const TvDownloadsPage({super.key, this.queueOnly = false});

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context, listen: true);
    if (dl == null) return const TvMissingPage(icon: Icons.download_outlined, title: 'Downloads aren\'t available here');
    final waiting = dl.waiting, done = dl.done, kept = dl.kept, temporary = dl.temporaries;
    final limit = dl.limitBytes;
    final anyRunning = waiting.any((e) => e.state == DownloadState.running || e.state == DownloadState.queued);
    final anyPaused = waiting.any((e) => e.state == DownloadState.paused);
    final queue = dl.queue;
    final items = queueOnly
        ? <Object>[
            for (var i = 0; i < queue.length; i++) (i + 1, queue[i]),
            if (queue.isEmpty) 'Nothing waiting to download.',
          ]
        : <Object>[
      if (waiting.isNotEmpty) ...['Downloading (${waiting.length})', ...waiting],
      if (kept.isNotEmpty) ...['Kept offline', ...kept],
      if (done.isNotEmpty) ...['Downloaded (${done.length})', ...done],
      // Saved while streaming (0.2.4).
      if (temporary.isNotEmpty) ...['Temporary copies (${temporary.length})', ...temporary],
      if (waiting.isEmpty && done.isEmpty && kept.isEmpty && temporary.isEmpty)
        'Nothing downloaded yet. Hold OK on anything from a server and choose Download.',
    ];
    return TvDetailPage<Object>(
      itemHeight: 60,
      header: TvDetailHeader(
        picture: TvColourPicture(colour: AppColors.accent, icon: Icons.download_for_offline),
        pictureWidth: 130,
        kind: 'Your servers',
        title: queueOnly ? 'Download queue' : 'Downloads',
        lines: [
          if (queueOnly)
            '${queue.length} in the queue · ${queue.where((e) => e.state == DownloadState.running).length} downloading now'
          else
            limit == null ? '${fileSizeText(dl.usedBytes)} used' : '${fileSizeText(dl.usedBytes)} of ${fileSizeText(limit)} used',
          ?dl.status,
        ],
        buttons: [
          if (anyRunning)
            TvButton(key: const ValueKey('tv-downloads-pause-all'), label: 'Pause all', icon: Icons.pause, onPressed: dl.pauseAll),
          if (anyPaused)
            TvButton(key: const ValueKey('tv-downloads-resume-all'), label: 'Carry on with all', icon: Icons.play_arrow, onPressed: dl.resumeAll),
          if (!queueOnly)
            TvButton(
              key: const ValueKey('tv-downloads-queue'),
              label: queue.isEmpty ? 'Queue' : 'Queue (${queue.length})',
              icon: Icons.queue_outlined,
              onPressed: () => context.read<AppNav>().openDownloadQueue(),
            ),
          TvIconButton(
            icon: Icons.more_horiz,
            label: 'More options',
            onPressed: () => showTvOptions(context, title: 'Downloads', options: [
              TvOption('Download settings', Icons.tune,
                  () => context.read<AppNav>().openSettings('server', setting: 'downloads-folder')),
              TvOption('Download or Keep offline?', Icons.help_outline, opensMore: true, () => showDownloadHelp(context)),
              if (dl.entries.isNotEmpty)
                TvOption('Remove all downloads', Icons.delete_outline, opensMore: true, () {
                  tvConfirm(context,
                      title: 'Remove all downloads?',
                      subtitle: 'Everything streams from the server again',
                      yes: 'Remove them all',
                      run: dl.removeAll);
                }),
            ]),
          ),
        ],
      ),
      items: items,
      itemBuilder: (context, x, i, node) => switch (x) {
        String s => TvListHeading(s),
        KeepOffline k => _KeptRow(keep: k, node: node),
        DownloadEntry e => _DownloadRow(entry: e, node: node),
        (int n, DownloadEntry e) => _DownloadRow(entry: e, node: node, position: n),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.entry, required this.node, this.position});
  final DownloadEntry entry;
  final FocusNode node;

  /// Its place in the queue (the queue page), shown instead of its kind's icon.
  final int? position;

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context)!;
    final e = entry;
    final video = e.kind == DownloadKind.video;
    final problem = e.state == DownloadState.failed || e.state == DownloadState.noRoom;
    final running = e.state == DownloadState.running;
    // The queue page shows every waiting one's bar (grey until it starts).
    final bar = !problem && !e.isDone && (running || position != null);
    return TvRow(
      key: ValueKey('tv-download:${e.id}'),
      focusNode: node,
      height: 60,
      leading: position == null
          ? Icon(video ? Icons.movie_outlined : (e.book ? Icons.menu_book_outlined : Icons.music_note_outlined))
          : CircleAvatar(
              radius: 14,
              backgroundColor: running ? AppColors.accent : AppColors.surfaceHigh,
              child: Text('$position', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
      title: e.title,
      subtitle: [if (e.subtitle.isNotEmpty) e.subtitle, dl.statusOf(e)].join(' · '),
      trailing: problem
          ? Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error)
          : (bar
              ? SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: e.expected != null && e.expected! > 0 ? e.progress.clamp(0.0, 1.0) : (running ? null : 0),
                    minHeight: 4,
                    color: running ? AppColors.accent : AppColors.textDim,
                  ),
                )
              : null),
      focusedHint: 'Hold OK for options',
      onPressed: () => e.isDone ? _play(context, e) : _options(context, e),
      onHold: () => _options(context, e),
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

  static Future<void> _options(BuildContext context, DownloadEntry e) {
    final dl = downloadsOf(context)!;
    final problem = e.state == DownloadState.failed || e.state == DownloadState.noRoom;
    return showTvOptions(context, title: e.title, subtitle: dl.statusOf(e), options: [
      if (e.isDone) TvOption('Play', Icons.play_arrow, () => _play(context, e)),
      if (e.state == DownloadState.running || e.state == DownloadState.queued)
        TvOption('Pause', Icons.pause, () => dl.pause(e.id)),
      if (e.state == DownloadState.paused) TvOption('Carry on', Icons.play_arrow, () => dl.resume(e.id)),
      if (problem) TvOption('Try again', Icons.refresh, () => dl.retry(e.id)),
      if (e.isTemporary) TvOption('Keep this copy', Icons.push_pin_outlined, () => dl.keepCopies([e.id])),
      if (e.isDone && dl.foldersFor(e).isNotEmpty)
        TvOption('Make it mine', Icons.drive_file_move_outline, opensMore: true, () => tvMakeItMine(context, e)),
      TvOption(e.isDone ? (e.isTemporary ? 'Remove temporary copy' : 'Remove download') : 'Stop downloading',
          e.isDone ? Icons.delete_outline : Icons.close,
          () => dl.remove([e.id])),
    ]);
  }
}

class _KeptRow extends StatelessWidget {
  const _KeptRow({required this.keep, required this.node});
  final KeepOffline keep;
  final FocusNode node;

  @override
  Widget build(BuildContext context) {
    void stop() => tvStopKeeping(context, (kind: keep.kind, key: keep.key, label: keep.label));
    return TvRow(
      key: ValueKey('tv-kept:${keep.id}'),
      focusNode: node,
      height: 60,
      leading: const Icon(Icons.offline_pin_outlined),
      title: keep.label,
      subtitle: '${keep.kind.label} · ${keep.quality.label}',
      focusedHint: 'OK to stop keeping it offline',
      onPressed: stop,
      onHold: stop,
    );
  }
}
