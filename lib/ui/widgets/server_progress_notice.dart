// Film collections plan, step 6 (9 Nov 2026; the user: "When servers are scanning, add a
// notification that shows the process and only goes away when closed or once the server work
// is completed"). A small card in the corner while any server is being read: the music server,
// Jellyfin servers' videos (with their pictures) and Audiobookshelf servers' books, each with
// what it's doing and a bar when there's a count. It goes when every server is done, or when
// closed (then it comes back with the next read). On the TV it sits top right out of the
// remote's way and goes when the work is done.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/server_books.dart';
import '../../state/server_reader.dart';
import '../../state/server_videos.dart';
import '../../state/servers_model.dart';
import '../theme.dart';

/// One server being read: its name and what it's doing ("Reading Films 120 / 5,900").
typedef ServerWork = ({String name, String doing});

/// Every server being read now.
List<ServerWork> serverWorkNow({
  required LibraryModel library,
  ServersModel? servers,
  List<ServerReader> readers = const [],
}) {
  final out = <ServerWork>[];
  final music = library.serverSync.value;
  if (music != null) out.add((name: 'Music server', doing: music));
  for (final r in readers) {
    for (final s in servers?.all ?? const <ServerEntry>[]) {
      if (r.reads(s) && r.isSyncing(s)) {
        // Between steps (the list read, the pictures not started yet) its line is the usual
        // "Signed in as … · read just now", with a green dot: say it's finishing instead.
        final between = r.okFor(s) == true;
        out.add((name: '${s.name} · ${r.readsKind == MediaKind.videos ? 'Videos' : 'Audiobooks'}', doing: between ? 'Finishing…' : r.statusFor(s)));
      }
    }
  }
  return out;
}

/// "120 / 5900" in [text] as a fraction, or null (the bar then just moves).
double? progressIn(String text) {
  final m = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(text);
  if (m == null) return null;
  final done = int.parse(m.group(1)!), total = int.parse(m.group(2)!);
  return total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

/// The notice, for a Stack over the whole app ([tv]: the TV's place and size).
class ServerProgressNotice extends StatefulWidget {
  const ServerProgressNotice({super.key, this.tv = false});

  final bool tv;

  @override
  State<ServerProgressNotice> createState() => _ServerProgressNoticeState();
}

class _ServerProgressNoticeState extends State<ServerProgressNotice> {
  bool _closed = false;

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryModel>();
    final servers = Provider.of<ServersModel?>(context, listen: false);
    final readers = <ServerReader>[
      ?Provider.of<ServerVideosModel?>(context, listen: false),
      ?Provider.of<ServerBooksModel?>(context, listen: false),
    ];
    return ListenableBuilder(
      listenable: Listenable.merge([library.serverSync, ?servers, ...readers]),
      builder: (context, _) {
        final work = serverWorkNow(library: library, servers: servers, readers: readers);
        // All done: closing it only lasts until the next read starts.
        if (work.isEmpty) _closed = false;
        if (work.isEmpty || _closed) return const Positioned(right: 0, bottom: 0, child: SizedBox.shrink());
        final size = MediaQuery.sizeOf(context);
        final width = (widget.tv ? 380.0 : 330.0).clamp(0.0, size.width - 24);
        final card = _card(context, work, width);
        return Positioned(
          right: widget.tv ? 32 : 12,
          top: widget.tv ? 24 : null,
          bottom: widget.tv ? null : MediaQuery.paddingOf(context).bottom + (size.width < 600 ? 150 : 104),
          // On the TV the remote's focus never lands on it.
          child: widget.tv ? ExcludeFocus(child: card) : card,
        );
      },
    );
  }

  Widget _card(BuildContext context, List<ServerWork> work, double width) {
    final t = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('server-progress'),
      color: AppColors.surfaceHigh,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 8, widget.tv ? 14 : 4, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(work.length == 1 ? 'Reading a server' : 'Reading ${work.length} servers',
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (!widget.tv)
                IconButton(
                  key: const ValueKey('server-progress-close'),
                  // (No tooltip: it sits above the app's pages, outside their Overlay.)
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _closed = true),
                )
              else
                const SizedBox(height: 32),
            ]),
            for (final w in work) ...[
              const SizedBox(height: 6),
              Padding(
                padding: EdgeInsets.only(right: widget.tv ? 0 : 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(w.doing, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: progressIn(w.doing), minHeight: 4),
                  ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
