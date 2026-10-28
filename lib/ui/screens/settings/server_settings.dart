// Settings › Servers (redesigned in 0.1.46): your servers for music, audiobooks and videos.
//
// "Add a server" (or "Add a … server" under a section) asks for the kind of server, a name, its
// address and sign-in, and what it's used for; "Test connection" checks it's there and what it
// is. Each section (Music, Audiobooks, Videos) lists the servers that can hold that kind, each
// with a switch to use it for that kind and a ⋮ menu (Edit, Test connection, Sync now, Make this
// the main music server, Remove). A server that holds all three kinds shows in all three.
//
// Music and audiobooks stream from one Subsonic server at a time: that's the main music server,
// kept by LibraryModel (connect, sync, forget, the password in protected storage, asking before
// plain http). Since 0.2.1 Jellyfin servers switched on for Videos are read into the Videos tab
// by ServerVideosModel (state/server_videos.dart): their card says how that went, and its ⋮ menu
// has Sync now, Libraries… and Sign out on this device. The others are saved and tested by
// ServersModel (state/servers_model.dart) and used as soon as their kind of server is supported.
// The list at the bottom says which kinds work now.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/subsonic_client.dart';
import '../../../state/library_model.dart';
import '../../../state/server_videos.dart';
import '../../../state/servers_model.dart';
import '../../theme.dart';
import 'download_settings.dart';
import 'settings_widgets.dart';
import '../../tv/tv_focus.dart' show tvModeOf;
import '../../tv/tv_keyboard.dart' show TvTextField;

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
          // Downloading from the servers (0.2.3).
          const DownloadSettings(),
          // Temporary copies of what streams (0.2.4).
          const TemporaryCopySettings(),
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
    final all = servers.serversFor(kind);
    // On a TV, a server that can't play this kind yet isn't listed under it (0.2.5): the one
    // Jellyfin server showed three times, twice switched on but "Coming later".
    final list = tvModeOf(context) ? [for (final s in all) if (s.type.playsKind(kind) || s.type.streams) s] : all;
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
            child: Text(
              all.isEmpty ? 'No $noun servers yet.' : 'Playing ${kind.lower} from ${all.first.type.label} servers is coming in a later update.',
              style: TextStyle(color: AppColors.textDim),
            ),
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
    // Jellyfin's videos (0.2.1); absent in tests that build the page on its own.
    final serverVideos = Provider.of<ServerVideosModel?>(context);
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
    } else if (kind == MediaKind.videos && s.type.playsKind(kind) && serverVideos != null) {
      // A Jellyfin server's videos (0.2.1): signed in, how many, when it was last read.
      status = serverVideos.statusFor(s);
      ok = serverVideos.okFor(s);
    } else if (s.type.streams) {
      status =
          'Saved. One ${s.type.label} server can stream at a time for now: use "Make this the main music '
          'server" to switch to this one.';
    } else {
      status = 'Saved. Playing ${kind.lower} from ${s.type.label} servers is coming in a later update.';
    }
    final readsVideos = kind == MediaKind.videos && s.type.playsKind(kind) && serverVideos != null && inUse;

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
                        if (!s.type.playsKind(kind)) const _Tag('Coming later'),
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
                    child: _MenuRow(Icons.edit_outlined, 'Edit…'),
                  ),
                  const PopupMenuItem(
                    value: 'test',
                    child: _MenuRow(Icons.network_check, 'Test connection'),
                  ),
                  if (s.isMain && lib.serverEnabled)
                    PopupMenuItem(
                      value: 'sync',
                      enabled: !lib.busy,
                      child: const _MenuRow(Icons.sync, 'Sync now'),
                    ),
                  if (readsVideos) ...[
                    PopupMenuItem(
                      value: 'video-sync',
                      enabled: !serverVideos.isSyncing(s),
                      child: const _MenuRow(Icons.sync, 'Sync now'),
                    ),
                    const PopupMenuItem(
                      value: 'libraries',
                      child: _MenuRow(Icons.video_library_outlined, 'Libraries…'),
                    ),
                    const PopupMenuItem(
                      value: 'sign-out',
                      child: _MenuRow(Icons.logout, 'Sign out on this device'),
                    ),
                  ],
                  if (!s.isMain && s.type == ServerType.subsonic)
                    const PopupMenuItem(
                      value: 'main',
                      child: _MenuRow(Icons.star_outline, 'Make this the main music server'),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: _MenuRow(Icons.delete_outline, s.isMain ? 'Forget this server' : 'Remove'),
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
      case 'video-sync':
        await context.read<ServerVideosModel>().sync(server);
      case 'libraries':
        await showServerLibraries(context, context.read<ServerVideosModel>(), server);
      case 'sign-out':
        await context.read<ServerVideosModel>().signOut(server);
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

/// A server menu item's icon and words (0.2.5). It was a ListTile; with the TV's remote (which
/// lets anything that could be tapped take focus) the remote stopped on that inner row, and OK
/// pressed the row, which does nothing, instead of the menu item: no choice in the menu worked
/// on the TV. ExcludeFocus keeps the remote on the menu item itself.
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => ExcludeFocus(child: ListTile(leading: Icon(icon), title: Text(label)));
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
            t.playsNow.isEmpty
                ? 'Coming later'
                : t.playsNow.length == t.can.length
                ? 'Works now'
                : '${[for (final k in t.playsNow) k.label].join(', ')} work now',
            style: TextStyle(color: t.playsNow.isNotEmpty ? Colors.greenAccent : AppColors.textDim, fontSize: 12),
          ),
        ),
    ],
  );
}

/// A Jellyfin server's libraries (0.2.1), each with a box to show it in the Videos tab or leave
/// it out.
Future<void> showServerLibraries(BuildContext context, ServerVideosModel model, ServerEntry server) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => ListenableBuilder(
        listenable: model,
        builder: (ctx, _) {
          final views = model.librariesOf(server);
          return AlertDialog(
            title: Text('${server.name}: libraries'),
            content: SizedBox(
              width: 420,
              child: views.isEmpty
                  ? const Text('No video libraries found yet. Use Sync now to read the server.')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Untick a library to leave its videos out of the Videos tab.',
                          style: TextStyle(fontSize: 12, color: AppColors.textDim),
                        ),
                        const SizedBox(height: 8),
                        for (final v in views)
                          CheckboxListTile(
                            key: ValueKey('library-${v.id}'),
                            value: model.isLibraryShown(server, v.id),
                            title: Text(v.name),
                            onChanged: model.isSyncing(server) ? null : (on) => model.setLibraryShown(server, v.id, on ?? true),
                          ),
                      ],
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          );
        },
      ),
    );
