// Settings › Servers (redesigned in 0.1.46): your servers for music, audiobooks and videos.
//
// "Add a server" (or "Add a … server" under a section) asks for the kind of server, a name, its
// address and sign-in, and what it's used for; "Test connection" checks it's there and what it
// is. Each section (Music, Audiobooks, Videos) lists the servers that can hold that kind, each
// with a switch to use it for that kind and a ⋮ menu (Edit, Test connection, Sync now, Make this
// the main music server, Remove). A server that holds all three kinds shows in all three.
//
// Only Subsonic servers can stream so far, one at a time: that's the main music server, kept by
// LibraryModel (connect, sync, forget, the password in protected storage, asking before plain
// http). The others are saved and tested by ServersModel (state/servers_model.dart) and used as
// soon as their kind of server is supported. The list at the bottom says which kinds work now.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/subsonic_client.dart';
import '../../../state/library_model.dart';
import '../../../state/servers_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

part 'servers/server_dialog.dart';

/// An icon for each kind of server.
IconData serverIcon(ServerType t) => switch (t) {
  ServerType.subsonic => Icons.dns_outlined,
  ServerType.jellyfin => Icons.live_tv_outlined,
  ServerType.plex => Icons.play_circle_outline,
  ServerType.emby => Icons.tv_outlined,
  ServerType.audiobookshelf => Icons.menu_book_outlined,
  ServerType.hometunes => Icons.home_outlined,
};

/// Settings › Servers.
class ServerSettings extends StatefulWidget {
  const ServerSettings({super.key});

  @override
  State<ServerSettings> createState() => ServerSettingsState();
}

class ServerSettingsState extends State<ServerSettings> {
  // Used when the app didn't provide one (some tests build Settings pages on their own).
  ServersModel? _fallback;

  ServersModel _servers(BuildContext context) =>
      Provider.of<ServersModel?>(context) ??
      (_fallback ??= ServersModel(context.read<LibraryModel>().storage, context.read<LibraryModel>()));

  @override
  void dispose() {
    _fallback?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final servers = _servers(context);
    return ListenableBuilder(
      listenable: servers,
      builder: (context, _) => SettingsPageList(
        intro:
            'Stream from your own servers as well as playing your own files. A server can hold music, '
            'audiobooks and videos, and you can add as many as you like.',
        children: [
          SettingTarget(
            'add-server',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    key: const ValueKey('add-server'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add a server'),
                    onPressed: () => showServerDialog(context, servers),
                  ),
                  const SizedBox(width: 16),
                  if (lib.status != null)
                    Expanded(
                      child: Text(lib.status!, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          if (lib.error != null && lib.error!.toLowerCase().contains('server'))
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: _StatusLine(lib.error!, ok: false)),
          SettingTarget(
            'server',
            child: _ServerSection(kind: MediaKind.music, servers: servers),
          ),
          SettingTarget(
            'server-books',
            child: _ServerSection(kind: MediaKind.audiobooks, servers: servers),
          ),
          SettingTarget(
            'video-server',
            child: _ServerSection(kind: MediaKind.videos, servers: servers),
          ),
          const _ServerTypesNote(),
        ],
      ),
    );
  }
}

/// One section: "Music", "Audiobooks" or "Videos", its servers and an "Add a … server" button.
class _ServerSection extends StatelessWidget {
  final MediaKind kind;
  final ServersModel servers;
  const _ServerSection({required this.kind, required this.servers});

  @override
  Widget build(BuildContext context) {
    final list = servers.serversFor(kind);
    // "music", "audiobook", "video": for "No video servers yet." and "Add a video server".
    final noun = switch (kind) {
      MediaKind.music => 'music',
      MediaKind.audiobooks => 'audiobook',
      MediaKind.videos => 'video',
    };
    final subtitle = switch (kind) {
      MediaKind.music => 'Servers your music can stream from.',
      MediaKind.audiobooks => 'Servers your audiobooks can stream from. Their books show in the Books tab.',
      MediaKind.videos => 'Servers your videos can stream from.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupTitle(kind.label, subtitle),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('No $noun servers yet.', style: TextStyle(color: AppColors.textDim)),
          ),
        for (final s in list) _ServerCard(server: s, kind: kind, servers: servers),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: TextButton.icon(
            key: ValueKey('add-${kind.name}-server'),
            icon: const Icon(Icons.add, size: 18),
            label: Text('Add ${kind == MediaKind.audiobooks ? 'an' : 'a'} $noun server'),
            onPressed: () => showServerDialog(context, servers, forKind: kind),
          ),
        ),
      ],
    );
  }
}

/// A server in a section: what it is, how it's doing, a switch to use it for this kind, and a
/// menu.
class _ServerCard extends StatelessWidget {
  final ServerEntry server;
  final MediaKind kind;
  final ServersModel servers;
  const _ServerCard({required this.server, required this.kind, required this.servers});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final s = server;
    final accent = Theme.of(context).colorScheme.primary;
    // For the main server, "in use" follows LibraryModel's switches.
    final inUse = s.isMain
        ? (kind == MediaKind.music ? lib.serverEnabled : lib.serverEnabled && lib.serverBooks)
        : s.uses.contains(kind);
    final String status;
    bool? ok;
    if (s.isMain) {
      if (!lib.serverEnabled) {
        status = 'Switched off: its music and audiobooks are hidden.';
      } else if (kind == MediaKind.music) {
        status = 'Connected · ${servers.mainSongCount} songs';
        ok = true;
      } else {
        status = lib.serverBooks ? 'Connected · its audiobooks show in the Books tab' : 'Its audiobooks are left out';
        ok = lib.serverBooks;
      }
    } else if (s.type.streams) {
      status =
          'Saved. One ${s.type.label} server can stream at a time for now: use "Make this the main music '
          'server" to switch to this one.';
    } else {
      status = 'Saved. Playing from ${s.type.label} servers is coming in a later update.';
    }

    return Padding(
      key: ValueKey('server-${s.id}-${kind.name}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: AppShape.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.withValues(alpha: 0.18),
                child: Icon(serverIcon(s.type), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (s.isMain) _Tag('Main music server', color: accent),
                        if (!s.type.streams) const _Tag('Coming later'),
                      ],
                    ),
                    Text(
                      '${s.type.label} · ${s.url}${s.username.isEmpty ? '' : ' · ${s.username}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textDim, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    _StatusLine(status, ok: ok),
                    if (s.lastCheck != null) ...[
                      const SizedBox(height: 2),
                      _StatusLine('Last test: ${s.lastCheck}', ok: s.reachable),
                    ],
                  ],
                ),
              ),
              Switch(
                key: ValueKey('use-${s.id}-${kind.name}'),
                value: inUse,
                onChanged: s.isMain && lib.busy ? null : (on) => servers.setUse(s, kind, on),
              ),
              PopupMenuButton<String>(
                key: ValueKey('server-menu-${s.id}-${kind.name}'),
                tooltip: 'More',
                onSelected: (v) => _act(context, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit…')),
                  ),
                  const PopupMenuItem(
                    value: 'test',
                    child: ListTile(leading: Icon(Icons.network_check), title: Text('Test connection')),
                  ),
                  if (s.isMain && lib.serverEnabled)
                    PopupMenuItem(
                      value: 'sync',
                      enabled: !lib.busy,
                      child: const ListTile(leading: Icon(Icons.sync), title: Text('Sync now')),
                    ),
                  if (!s.isMain && s.type == ServerType.subsonic)
                    const PopupMenuItem(
                      value: 'main',
                      child: ListTile(
                        leading: Icon(Icons.star_outline),
                        title: Text('Make this the main music server'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(s.isMain ? 'Forget this server' : 'Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case 'edit':
        await showServerDialog(context, servers, editing: server);
      case 'test':
        messenger.showSnackBar(
          SnackBar(content: Text('Testing ${server.name}…'), duration: const Duration(seconds: 2)),
        );
        final r = await servers.test(server);
        messenger.showSnackBar(SnackBar(content: Text(r.message)));
      case 'sync':
        await lib.syncServer();
      case 'main':
        var err = await servers.makeMain(server);
        if (err == LibraryModel.httpConsentNeeded && context.mounted) {
          err = await askPlainHttp(context)
              ? await servers.makeMain(server, allowPlainHttp: true)
              : 'Not switched. Set up https on the server, or connect over your home network or Tailscale.';
        }
        messenger.showSnackBar(SnackBar(content: Text(err ?? '${server.name} is now the main music server.')));
      case 'remove':
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(server.isMain ? 'Forget ${server.name}?' : 'Remove ${server.name}?'),
            content: Text(
              server.isMain
                  ? 'Its music and audiobooks stop showing in HomeTunes, and its sign-in is forgotten. '
                        'Your own files aren\'t touched.'
                  : 'It\'s taken off this list and its sign-in is forgotten.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(server.isMain ? 'Forget' : 'Remove')),
            ],
          ),
        );
        if (yes == true) await servers.remove(server);
    }
  }
}

/// A small rounded label: "Main music server", "Coming later".
class _Tag extends StatelessWidget {
  final String text;
  final Color? color;
  const _Tag(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: AppShape.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A line of status with a coloured dot: green (fine), red (a problem) or none.
class _StatusLine extends StatelessWidget {
  final String text;
  final bool? ok;
  const _StatusLine(this.text, {this.ok});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (ok != null)
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 6),
          child: Icon(Icons.circle, size: 8, color: ok! ? Colors.greenAccent : Colors.redAccent),
        ),
      Expanded(
        child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
      ),
    ],
  );
}

/// Which kinds of server work now, and which are coming.
class _ServerTypesNote extends StatelessWidget {
  const _ServerTypesNote();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SettingsGroupTitle('Kinds of server', 'What HomeTunes can play from now, and what\'s coming.'),
      for (final t in ServerType.values)
        ListTile(
          dense: true,
          leading: Icon(serverIcon(t)),
          title: Text(t.label),
          subtitle: Text('${t.about} Holds: ${[for (final k in t.can) k.lower].join(', ')}.'),
          trailing: Text(
            t.streams ? 'Works now' : 'Coming later',
            style: TextStyle(color: t.streams ? Colors.greenAccent : AppColors.textDim, fontSize: 12),
          ),
        ),
    ],
  );
}
