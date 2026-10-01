// The Details page for videos (0.1.44, the user's request: "Music and audio books allow for
// viewing the file details, I'd like this for the videos too"). Like the Details page for songs,
// albums and books (details_screen.dart, whose cards and table it shares):
//  * one video: where it is (folder, file, size, which video folder), every detail the Videos
//    tab shows with where it came from (its .nfo file, the series' tvshow.nfo, the file's tags,
//    the folder or file name, the video itself, or your edit), what's inside the file (format,
//    picture, frame rate, each sound track and subtitle, chapters; asked of the video engine,
//    services/video_probe.dart), what its .nfo file and tags say, and the files beside it that
//    HomeTunes uses (.nfo files, the collection's poster, subtitle files);
//  * a collection: its folders and files, its details and where they come from, and each video
//    (open one to see its own).
// Opened from "Details…" in a video's or a collection's right-click / press-and-hold menu, the
// video player page and a collection's page. It only reads; nothing is changed.
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../services/media_details.dart';
import '../../services/video_details.dart';
import '../../services/video_probe.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';
import 'details_screen.dart';
import 'video_player_screen.dart' show languageName;
import 'videos_screen.dart' show videoLength;

/// Opens the Details page for one video.
Future<void> openVideoDetails(BuildContext context, VideoItem v) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => VideoDetailsScreen(videoId: v.id)));

/// Opens the Details page for a collection.
Future<void> openCollectionDetails(BuildContext context, VideoCollection c) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(builder: (_) => CollectionDetailsScreen(name: c.name)));

/// How the page asks what's inside a file (the video engine; tests use a stand-in).
@visibleForTesting
Future<VideoProbe?> Function(String path) videoProbe = probeVideo;

// ---- plain words for what the engine reports ----

/// "Matroska (MKV)", "MP4"…
String containerName(String? format, String fallback) {
  final f = (format ?? '').toLowerCase();
  if (f.isEmpty) return fallback;
  if (f.contains('matroska') || f == 'mkv') return 'Matroska (MKV)';
  if (f.contains('webm')) return 'WebM';
  if (f.contains('mp4') || f.contains('mov')) return 'MP4 / QuickTime';
  if (f.contains('avi')) return 'AVI';
  if (f.contains('asf')) return 'Windows Media (ASF)';
  if (f.contains('mpegts')) return 'MPEG transport stream';
  if (f.contains('mpeg')) return 'MPEG';
  if (f.contains('flv')) return 'Flash video (FLV)';
  if (f.contains('ogg')) return 'Ogg';
  return format!.toUpperCase();
}

const _codecs = {
  'hevc': 'H.265 (HEVC)',
  'h264': 'H.264 (AVC)',
  'av1': 'AV1',
  'vp9': 'VP9',
  'vp8': 'VP8',
  'mpeg4': 'MPEG-4 Part 2 (DivX / Xvid)',
  'mpeg2video': 'MPEG-2',
  'mpeg1video': 'MPEG-1',
  'vc1': 'VC-1',
  'wmv3': 'Windows Media Video 9',
  'theora': 'Theora',
  'mjpeg': 'Motion JPEG',
  'ac3': 'Dolby Digital (AC3)',
  'eac3': 'Dolby Digital Plus (E-AC3)',
  'truehd': 'Dolby TrueHD',
  'dts': 'DTS',
  'aac': 'AAC',
  'mp3': 'MP3',
  'mp2': 'MP2',
  'opus': 'Opus',
  'vorbis': 'Vorbis',
  'flac': 'FLAC',
  'alac': 'Apple Lossless',
  'wmav2': 'Windows Media Audio',
  'ass': 'Styled text (ASS)',
  'ssa': 'Styled text (SSA)',
  'subrip': 'Text (SRT)',
  'webvtt': 'Text (WebVTT)',
  'mov_text': 'Text (MP4)',
  'hdmv_pgs_subtitle': 'Pictures (Blu-ray)',
  'dvd_subtitle': 'Pictures (DVD)',
  'dvb_subtitle': 'Pictures (TV broadcast)',
};

/// "H.265 (HEVC)", "Dolby Digital (AC3)", "Styled text (ASS)"…
String codecName(String? codec) {
  if (codec == null) return 'Unknown format';
  return _codecs[codec.toLowerCase()] ??
      (codec.toLowerCase().startsWith('pcm') ? 'Uncompressed (PCM)' : codec.toUpperCase());
}

/// "Mono", "Stereo", "5.1", "7.1", "3 channels".
String? channelsName(int? n) => switch (n) {
  null => null,
  1 => 'Mono',
  2 => 'Stereo',
  6 => '5.1',
  8 => '7.1',
  _ => '$n channels',
};

/// One line for a track: "English · "Signs & Songs" · Styled text (ASS) · shown first".
String trackLine(ProbeTrack t) {
  final lang = t.language == null ? null : (languageName(t.language) ?? t.language);
  final parts = <String>[
    if (t.kind == 'video') ...[
      codecName(t.codec),
      if (t.width != null && t.height != null) '${t.width}×${t.height}',
      if (t.fps != null && t.fps! > 0) '${_fps(t.fps!)} frames a second',
    ] else ...[
      ?lang,
      if (t.title != null && t.title != lang) '"${t.title}"',
      codecName(t.codec),
      if (t.kind == 'audio') ...[
        ?channelsName(t.channels),
        if (t.sampleRate != null) '${(t.sampleRate! / 1000).toStringAsFixed(t.sampleRate! % 1000 == 0 ? 0 : 1)} kHz',
      ],
      if (t.forced) 'forced',
      if (t.hearingImpaired) 'for the hard of hearing',
      if (t.isDefault) t.kind == 'audio' ? 'plays first' : 'shown first',
    ],
  ];
  return parts.join(' · ');
}

String _fps(double f) {
  final r = (f * 1000).round() / 1000;
  return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}

/// "about 5.2 Mbit/s" from a file's size and length.
String? overallBitRate(int? bytes, Duration length) {
  if (bytes == null || bytes <= 0 || length.inMilliseconds <= 0) return null;
  final bps = bytes * 8 / (length.inMilliseconds / 1000);
  return bps >= 1e6 ? 'about ${(bps / 1e6).toStringAsFixed(1)} Mbit/s' : 'about ${(bps / 1e3).round()} kbit/s';
}

String _date(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

// ---- one video ----

class VideoDetailsScreen extends StatelessWidget {
  final String videoId;
  const VideoDetailsScreen({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    final v = context.select<VideoLibraryModel, VideoItem?>((m) => m.byId(videoId));
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: v == null
          ? const Center(child: Text('This video isn\'t in your library any more.'))
          : _Page(
              kind: 'Video',
              title: v.title,
              subtitle: [v.collection, ?v.episodeLabel].join(' · '),
              children: [_VideoDetailsBody(key: ValueKey(v.id), video: v)],
            ),
    );
  }
}

/// The page's frame: what it is, the title, then the cards.
class _Page extends StatelessWidget {
  final String kind;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Page({required this.kind, required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            kind.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
}

/// One video's details. [flat] (inside a collection's list) leaves out the cards and the
/// "Where it is" part; what's inside the file is still asked for, once it's shown.
class _VideoDetailsBody extends StatefulWidget {
  final VideoItem video;
  final bool flat;
  const _VideoDetailsBody({super.key, required this.video, this.flat = false});

  @override
  State<_VideoDetailsBody> createState() => _VideoDetailsBodyState();
}

class _VideoDetailsBodyState extends State<_VideoDetailsBody> {
  late Future<VideoFileReport> _report;
  Future<VideoProbe?>? _probe;

  @override
  void initState() {
    super.initState();
    final model = context.read<VideoLibraryModel>();
    final v = widget.video;
    final c = model.collectionOf(v);
    _report = inspectVideo(
      shown: v,
      scanned: model.rawById(v.id) ?? v,
      roots: model.library.videoFolders,
      ownPicture: model.hasOwnPicture(v),
      ownSeasonTitle: c != null && v.season != null && model.hasOwnSeasonTitle(c, v.season!, v.subSeason),
    );
    // Only files inside the video folders are opened.
    final file = model.playableFile(v);
    if (file != null) _probe = videoProbe(file);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<VideoFileReport>(
    future: _report,
    builder: (context, snap) {
      if (snap.hasError) return Text('Couldn\'t read the details: ${snap.error}');
      final d = snap.data;
      if (d == null) return const _Waiting();
      final model = context.read<VideoLibraryModel>();
      final v = widget.video;
      final fileLine = DetailsLine(
        Icons.insert_drive_file_outlined,
        '${d.fileName} · ${d.format}${d.sizeBytes != null ? ' · ${fileSize(d.sizeBytes!)}' : ''}'
        '${d.modified != null ? ' · changed ${_date(d.modified!)}' : ''}',
      );
      final inside = _Inside(probe: _probe, sizeBytes: d.sizeBytes, format: d.format, fallbackLength: v.duration);
      final table = DetailsTable(rows: d.rows);
      final nfo = [for (final (k, x) in d.nfoSays) DetailsPair(k, x)];
      final tags = [for (final (k, x) in d.tagsSay) DetailsPair(k, x)];
      final beside = [for (final (name, use) in d.besideIt) DetailsPair(use, name)];
      if (widget.flat) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.problem != null) DetailsLine(Icons.warning_amber_outlined, d.problem!),
            fileLine,
            const SizedBox(height: 8),
            table,
            const DetailsHeading('What\'s inside the file'),
            inside,
            if (nfo.isNotEmpty) ...[const DetailsHeading('What its .nfo file says'), ...nfo],
            if (tags.isNotEmpty) ...[const DetailsHeading('What the file\'s tags say'), ...tags],
            if (beside.isNotEmpty) ...[const DetailsHeading('Files beside it that HomeTunes uses'), ...beside],
          ],
        );
      }
      const gap = SizedBox(height: 16);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailsCard(
            title: 'Where it is',
            children: [
              if (d.problem != null) DetailsLine(Icons.warning_amber_outlined, d.problem!),
              DetailsFolderLine(folder: d.folder, firstFile: v.path, roots: model.library.videoFolders),
              fileLine,
              DetailsLine(
                Icons.video_library_outlined,
                d.videoFolder == null
                    ? 'Not inside any of your video folders now'
                    : 'Found in your video folder ${d.videoFolder}',
              ),
            ],
          ),
          gap,
          DetailsCard(title: 'Details and where they come from', children: [table]),
          gap,
          DetailsCard(
            title: 'What\'s inside the file',
            subtitle: 'Read from the file just now by the video player.',
            children: [inside],
          ),
          if (nfo.isNotEmpty) ...[
            gap,
            DetailsCard(
              title: 'What its .nfo file says',
              subtitle: 'The details file beside the video.',
              children: nfo,
            ),
          ],
          if (tags.isNotEmpty) ...[
            gap,
            DetailsCard(
              title: 'What the file\'s tags say',
              subtitle: 'Read from the file just now, before any of your edits.',
              children: tags,
            ),
          ],
          if (beside.isNotEmpty) ...[gap, DetailsCard(title: 'Files beside it that HomeTunes uses', children: beside)],
        ],
      );
    },
  );
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(12),
    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
  );
}

/// What the video engine found inside the file.
class _Inside extends StatelessWidget {
  final Future<VideoProbe?>? probe;
  final int? sizeBytes;
  final String format;
  final Duration fallbackLength;
  const _Inside({required this.probe, required this.sizeBytes, required this.format, required this.fallbackLength});

  @override
  Widget build(BuildContext context) {
    if (probe == null) {
      return const DetailsLine(
        Icons.info_outline,
        'The file can\'t be opened from here, so what\'s inside it isn\'t known.',
      );
    }
    return FutureBuilder<VideoProbe?>(
      future: probe,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const _Waiting();
        final x = snap.data;
        if (x == null) {
          return const DetailsLine(
            Icons.warning_amber_outlined,
            'The video player couldn\'t open the file to look inside it.',
          );
        }
        final length = x.duration > Duration.zero ? x.duration : fallbackLength;
        final rate = overallBitRate(sizeBytes, length);
        String numbered(String what, int i, int n) => n == 1 ? what : '$what ${i + 1}';
        final video = x.video, audio = x.audio, subs = x.subtitles;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DetailsPair('Format', containerName(x.container, format)),
            if (length > Duration.zero) DetailsPair('Length', videoLength(length)),
            if (rate != null) DetailsPair('Bit rate', rate),
            DetailsPair('Chapters', x.chapters == 0 ? 'None' : '${x.chapters}'),
            if (video.isEmpty) const DetailsPair('Picture', 'None (sound only)'),
            for (final (i, t) in video.indexed) DetailsPair(numbered('Picture', i, video.length), trackLine(t)),
            if (audio.isEmpty) const DetailsPair('Sound', 'None'),
            for (final (i, t) in audio.indexed) DetailsPair(numbered('Sound', i, audio.length), trackLine(t)),
            if (subs.isEmpty) const DetailsPair('Subtitles', 'None inside the file'),
            for (final (i, t) in subs.indexed) DetailsPair(numbered('Subtitles', i, subs.length), trackLine(t)),
          ],
        );
      },
    );
  }
}

// ---- a collection ----

class CollectionDetailsScreen extends StatelessWidget {
  final String name;
  const CollectionDetailsScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final c = model.collectionNamed(name);
    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: c == null || c.videos.isEmpty
          ? const Center(child: Text('This collection isn\'t in your library any more.'))
          : _Page(kind: 'Collection', title: c.name, subtitle: c.category, children: [_CollectionBody(c)]),
    );
  }
}

class _CollectionBody extends StatefulWidget {
  final VideoCollection collection;
  const _CollectionBody(this.collection);

  @override
  State<_CollectionBody> createState() => _CollectionBodyState();
}

class _CollectionBodyState extends State<_CollectionBody> {
  late Future<VideoFileReport> _first;

  @override
  void initState() {
    super.initState();
    final model = context.read<VideoLibraryModel>();
    final v = widget.collection.videos.first;
    _first = inspectVideo(shown: v, scanned: model.rawById(v.id) ?? v, roots: model.library.videoFolders);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final c = widget.collection;
    final folders = {for (final v in c.videos) p.dirname(v.path)}.toList()..sort();
    final size = c.videos.fold<int>(0, (s, v) => s + (v.sizeBytes ?? 0));
    final formats = {for (final v in c.videos) v.format}.toList()..sort();
    final n = c.videos.length;
    final summary = [
      '$n video${n == 1 ? '' : 's'}',
      formats.join(', '),
      if (size > 0) fileSize(size),
      if (c.totalDuration > Duration.zero) '${videoLength(c.totalDuration)} in all',
    ].join(' · ');
    const shownFolders = 8;
    const gap = SizedBox(height: 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailsCard(
          title: 'Where it is',
          children: [
            for (final f in folders.take(shownFolders))
              DetailsFolderLine(
                folder: f,
                firstFile: c.videos.firstWhere((v) => p.dirname(v.path) == f).path,
                roots: model.library.videoFolders,
              ),
            if (folders.length > shownFolders)
              DetailsLine(Icons.folder_outlined, 'and ${folders.length - shownFolders} more folders'),
            DetailsLine(Icons.insert_drive_file_outlined, summary),
          ],
        ),
        gap,
        DetailsCard(
          title: 'Details and where they come from',
          subtitle: n > 1
              ? 'From the first video, unless the collection has its own. Open a video below to see its own.'
              : null,
          children: [
            FutureBuilder<VideoFileReport>(
              future: _first,
              builder: (context, snap) {
                final d = snap.data;
                if (d == null) {
                  return snap.hasError ? Text('Couldn\'t read the details: ${snap.error}') : const _Waiting();
                }
                return DetailsTable(rows: collectionRows(c, d.rows, model));
              },
            ),
          ],
        ),
        gap,
        DetailsCard(
          title: '$n video${n == 1 ? '' : 's'}',
          children: [
            for (final v in c.videos)
              ExpansionTile(
                key: ValueKey(v.id),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: Text([?v.episodeLabel, v.title].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  p.basename(v.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
                children: [_VideoDetailsBody(video: v, flat: true)],
              ),
          ],
        ),
      ],
    );
  }
}

/// A collection's own rows: its name, category, year and genre as its first video's (renamed),
/// its description (yours, or the series' tvshow.nfo) and its poster.
@visibleForTesting
List<DetailRow> collectionRows(VideoCollection c, List<DetailRow> firstVideo, VideoLibraryModel model) {
  DetailRow? of(String label) => firstVideo.where((r) => r.label == label).firstOrNull;
  DetailRow renamed(DetailRow? r, String label, String? value) {
    final shown = value ?? '–';
    if (r == null) return DetailRow(label, shown, value == null ? DetailSource.notSet : DetailSource.unknown);
    // The collection shows the earliest year / the most common genre: the first video's source
    // only explains it when they match.
    if (r.shown != shown) return DetailRow(label, shown, DetailSource.unknown);
    return DetailRow(label, shown, r.source, from: r.from, inFile: r.inFile);
  }

  final description = c.description;
  final ownPoster = model.hasOwnPoster(c);
  return [
    renamed(of('Collection'), 'Name', c.name),
    renamed(of('Category'), 'Category', c.category),
    renamed(of('Year'), 'Year', c.year?.toString()),
    renamed(of('Genre'), 'Genre', c.genre),
    description == null
        ? const DetailRow('Description', '–', DetailSource.notSet)
        : DetailRow(
            'Description',
            description.length > 80 ? '${description.substring(0, 80)}…' : description,
            model.hasOwnDescription(c) ? DetailSource.edit : DetailSource.showNfo,
          ),
    ownPoster
        ? const DetailRow('Poster', 'Picture you chose', DetailSource.edit)
        : c.cover != null
        ? DetailRow('Poster', 'Picture', DetailSource.picture, from: p.basename(c.cover!))
        : const DetailRow('Poster', 'The first video\'s picture', DetailSource.frame),
  ];
}
