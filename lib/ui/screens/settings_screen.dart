import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';

import '../../services/app_backup.dart';
import '../../services/subsonic_client.dart';
import '../../services/tag_writer.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          _FoldersSection(),
          Divider(height: 32),
          _CoversSection(),
          Divider(height: 32),
          _WriteTagsSection(),
          Divider(height: 32),
          _ServerSection(),
          Divider(height: 32),
          _BackupSection(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionTitle(this.title, [this.subtitle]);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(color: AppColors.textDim)),
          ],
        ]),
      );
}

// ---------------------------------------------------------------- folders

class _FoldersSection extends StatelessWidget {
  const _FoldersSection();

  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    if (Platform.isAndroid) {
      // Android 13+ uses "Music and audio"; older versions use storage.
      final perms = PermissionHandlerPlatform.instance;
      final statuses = await perms.requestPermissions([Permission.audio, Permission.storage]);
      final ok = statuses.values.any((s) => s.isGranted || s.isLimited);
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: const Text('HomeTunes needs permission to read your music.'),
          action: SnackBarAction(label: 'Open settings', onPressed: perms.openAppSettings),
        ));
        return;
      }
    }
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose your music folder');
    if (path == null) return;
    await lib.addFolder(path);
    final n = lib.tracks.where((t) => t.isLocal).length;
    messenger.showSnackBar(SnackBar(content: Text('Library now has $n local songs')));
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final localCount = lib.tracks.where((t) => t.isLocal).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle(
        'Music folders',
        'HomeTunes plays the MP3, FLAC, M4A, OGG, Opus and WAV files in these folders (and their subfolders).',
      ),
      for (final f in lib.folders)
        ListTile(
          leading: const Icon(Icons.folder),
          title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Remove folder',
            icon: const Icon(Icons.close),
            onPressed: lib.busy ? null : () => lib.removeFolder(f),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add folder'),
            onPressed: lib.busy ? null : () => _addFolder(context),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Rescan'),
            onPressed: lib.busy || lib.folders.isEmpty ? null : lib.scanLocal,
          ),
          Text(lib.busy ? (lib.status ?? 'Working…') : '$localCount songs found',
              style: const TextStyle(color: AppColors.textDim)),
        ]),
      ),
      if (lib.missingTracks.isNotEmpty) _MissingSongsTile(count: lib.missingTracks.length),
    ]);
  }
}

/// Songs HomeTunes knows about (edited, in playlists or liked) whose files
/// aren't on this device. They're kept in case the files come back.
class _MissingSongsTile extends StatelessWidget {
  final int count;
  const _MissingSongsTile({required this.count});

  Future<void> _showList(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final songs = lib.missingTracks;
    final forget = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count song${count == 1 ? '' : 's'} not on this device'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'These songs have edits or are in playlists / Liked Songs, but their files weren\'t found. '
              'They\'re skipped when playing. If the files come back – even in a different folder – '
              'everything is picked up again on the next scan.',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final t in songs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.path ?? '${t.artist} · ${t.album}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget them')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
        ],
      ),
    );
    if (forget != true || !context.mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget these songs?'),
        content: const Text('Their edits are deleted and they\'re removed from your playlists and Liked Songs. '
            'Your music files aren\'t touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget')),
        ],
      ),
    );
    if (sure == true) await lib.forgetMissing();
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.help_outline, color: AppColors.textDim),
        title: Text('$count song${count == 1 ? '' : 's'} not on this device'),
        subtitle: const Text('Their details and playlist places are kept in case they come back'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showList(context),
      );
}

// ---------------------------------------------------------------- server

class _ServerSection extends StatefulWidget {
  const _ServerSection();

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  late final TextEditingController _url, _user, _pass;
  late ServerConfig _shown;
  bool _connecting = false;
  bool _showPass = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<LibraryModel>().server;
    _shown = s;
    _url = TextEditingController(text: s.url);
    _user = TextEditingController(text: s.username);
    _pass = TextEditingController(text: s.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final lib = context.read<LibraryModel>();
    setState(() {
      _connecting = true;
      _message = null;
    });
    final err = await lib.connectServer(
      ServerConfig(url: _url.text.trim(), username: _user.text.trim(), password: _pass.text),
    );
    if (!mounted) return;
    final n = lib.tracks.where((t) => !t.isLocal).length;
    setState(() {
      _connecting = false;
      _messageIsError = err != null;
      _message = err ?? 'Connected — $n songs available from the server.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final hasServer = lib.server.isComplete;
    // Server details changed elsewhere (e.g. a restored backup): show them.
    final s = lib.server;
    if (!_connecting &&
        (s.url != _shown.url || s.username != _shown.username || s.password != _shown.password)) {
      _shown = s;
      _url.text = s.url;
      _user.text = s.username;
      _pass.text = s.password;
    }
    final remoteCount = lib.tracks.where((t) => !t.isLocal).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle(
        'Music server (optional)',
        'Stream from your own server as well. Works with anything that speaks the Subsonic API — '
            'Navidrome, Airsonic-Advanced, Gonic, Ampache and others.',
      ),
      if (hasServer)
        SwitchListTile(
          title: const Text('Include server music'),
          subtitle: Text(lib.serverEnabled ? '$remoteCount songs from ${lib.server.url}' : 'Local files only'),
          value: lib.serverEnabled,
          onChanged: lib.busy ? null : lib.setServerEnabled,
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'e.g. http://192.168.1.20:4533',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pass,
            obscureText: !_showPass,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
            onSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton.icon(
              icon: _connecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: Text(hasServer ? 'Save & reconnect' : 'Connect'),
              onPressed: _connecting || lib.busy ? null : _connect,
            ),
            const SizedBox(width: 12),
            if (hasServer && lib.serverEnabled)
              OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sync now'),
                onPressed: lib.busy ? null : lib.syncServer,
              ),
            const Spacer(),
            if (hasServer)
              TextButton(
                onPressed: lib.busy
                    ? null
                    : () {
                        lib.forgetServer();
                        _url.clear();
                        _user.clear();
                        _pass.clear();
                        setState(() => _message = null);
                      },
                child: const Text('Forget server'),
              ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Icon(_messageIsError ? Icons.error_outline : Icons.check_circle_outline,
                    color: _messageIsError ? Colors.redAccent : Colors.greenAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_message!)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- cover art

class _CoversSection extends StatelessWidget {
  const _CoversSection();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle('Online lookups'),
      SwitchListTile(
        title: const Text('Find missing covers online'),
        subtitle: const Text(
          'Offer to look up album covers on MusicBrainz / Cover Art Archive when a song or album '
          'has an artist or album name. Only the artist, album and song names are sent.',
        ),
        value: lib.onlineCovers,
        onChanged: lib.setOnlineCovers,
      ),
      SwitchListTile(
        title: const Text('Find missing song details online'),
        subtitle: const Text(
          'Offer to look up year, artist, album, album artist, genre and track numbers on MusicBrainz, '
          'from the edit screen and on album pages with missing details.',
        ),
        value: lib.onlineDetails,
        onChanged: lib.setOnlineDetails,
      ),
    ]);
  }
}

// ---------------------------------------------------------------- write tags

class _WriteTagsSection extends StatefulWidget {
  const _WriteTagsSection();

  @override
  State<_WriteTagsSection> createState() => _WriteTagsSectionState();
}

class _WriteTagsSectionState extends State<_WriteTagsSection> {
  bool _backup = true;
  bool _running = false;

  Future<void> _write() async {
    final lib = context.read<LibraryModel>();
    final tracks = lib.tracksWithWritableEdits;
    if (tracks.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write ${tracks.length} song${tracks.length == 1 ? '' : 's'} to files?'),
        content: Text(
          'Your HomeTunes edits (details and covers) will be saved into the music files themselves, so other '
          'players and devices see them too.\n\n'
          '${_backup ? 'A backup copy of each file is made first.' : 'No backup copies will be made.'}\n\n'
          'Anything a file type can\'t store (for example album artist in M4A, or covers in WAV) stays as a '
          'HomeTunes edit.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write to files')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _running = true);
    List<TagWriteResult> results;
    try {
      results = await lib.writeEditsToFiles(tracks, backup: _backup);
    } catch (e) {
      results = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Writing tags failed: $e')));
      }
    }
    if (!mounted) return;
    setState(() => _running = false);

    final failed = results.where((r) => !r.ok).toList();
    final written = results.length - failed.length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(failed.isEmpty ? 'Done' : 'Finished with some problems'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$written file${written == 1 ? '' : 's'} updated.'),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${failed.length} couldn\'t be written (their edits are kept in HomeTunes):'),
              const SizedBox(height: 4),
              for (final r in failed.take(8))
                Text('• ${r.path.split(RegExp(r'[\\/]')).last}: ${r.error}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
              if (failed.length > 8) Text('…and ${failed.length - 8} more', style: const TextStyle(fontSize: 12)),
            ],
            if (_backup && results.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Backups are in:', style: TextStyle(fontSize: 12)),
              SelectableText(lib.backupRoot, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final writable = lib.tracksWithWritableEdits.length;
    final unwritable = lib.unwritableEditCount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle(
        'Save edits into music files',
        'Edits you make in HomeTunes are normally kept in the app only. This writes them into the files '
            '(MP3, FLAC, M4A, WAV) so every player sees them.',
      ),
      SwitchListTile(
        title: const Text('Back up each file first'),
        subtitle: const Text('Keeps a copy of the original in the HomeTunes data folder'),
        value: _backup,
        onChanged: _running ? null : (v) => setState(() => _backup = v),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            icon: _running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_alt),
            label: Text(writable == 0 ? 'No edits to write' : 'Write $writable song${writable == 1 ? '' : 's'} to files…'),
            onPressed: _running || lib.busy || writable == 0 ? null : _write,
          ),
          if (unwritable > 0)
            Text(
              '$unwritable edited song${unwritable == 1 ? '' : 's'} can\'t be written (server songs or OGG/Opus)',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- backup

class _BackupSection extends StatefulWidget {
  const _BackupSection();

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _includePassword = false;
  bool _includeCoverCache = true;
  bool _working = false;

  String get _fileName {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'HomeTunes-backup-${d.year}-${two(d.month)}-${two(d.day)}.${AppBackup.fileExtension}';
  }

  Future<void> _export() async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      final bytes = await lib.createBackup(
        includePassword: _includePassword,
        includeCoverCache: _includeCoverCache,
      );
      final saved = await FilePicker.saveFile(
        fileName: _fileName,
        bytes: bytes,
        dialogTitle: 'Save HomeTunes backup',
      );
      if (saved != null) {
        final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        messenger.showSnackBar(SnackBar(content: Text('Backup saved ($mb MB)')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t make the backup: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    final lib = context.read<LibraryModel>();
    final playlists = context.read<PlaylistsModel>();
    final messenger = ScaffoldMessenger.of(context);

    BackupContents backup;
    try {
      final file = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose a HomeTunes backup');
      final path = file?.path;
      if (path == null) return;
      setState(() => _working = true);
      backup = AppBackup.read(await File(path).readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'Couldn\'t read it: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _working = false);

    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (backup.created != null)
            Text('Made ${_date(backup.created!)}${backup.from != null ? ' on ${_os(backup.from!)}' : ''}'),
          const SizedBox(height: 8),
          Text('• ${backup.songCount} songs in the library\n'
              '• ${backup.playlistCount} playlist${backup.playlistCount == 1 ? '' : 's'}, '
              '${backup.likedCount} liked song${backup.likedCount == 1 ? '' : 's'}\n'
              '• ${backup.editCount} edited song${backup.editCount == 1 ? '' : 's'}\n'
              '• ${backup.folders.length} music folder${backup.folders.length == 1 ? '' : 's'}'
              '${backup.hasPassword ? '\n• server password included' : ''}'),
          const SizedBox(height: 12),
          const Text(
            'Replace: this device\'s HomeTunes data becomes the backup\'s.\n'
            'Merge: the backup\'s playlists, likes and edits are added to what\'s here.\n\n'
            'Your music files aren\'t touched. A copy of the current data is saved first.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Merge')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Replace')),
        ],
      ),
    );
    if (merge == null || !mounted) return;

    setState(() => _working = true);
    try {
      final result = await lib.restoreBackup(backup, merge: merge, reloadOthers: playlists.load);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup restored'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${lib.tracks.length} songs are available on this device.'),
            if (lib.missingTracks.isNotEmpty)
              Text('${lib.missingTracks.length} songs from the backup aren\'t here yet; their details and playlist '
                  'places are kept and are picked up when you add the folder they\'re in.'),
            if (result.missingFolders.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('These music folders don\'t exist on this device, so they weren\'t added. '
                  'Use "Add folder" to point HomeTunes at your music here:'),
              for (final f in result.missingFolders)
                Text('• $f', style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
            if (result.needsPassword) ...[
              const SizedBox(height: 12),
              const Text('The server password wasn\'t in the backup: enter it under Music server.'),
            ],
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static String _os(String os) => switch (os) {
        'windows' => 'Windows',
        'android' => 'Android',
        'macos' => 'macOS',
        'linux' => 'Linux',
        'ios' => 'iOS',
        _ => os,
      };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final busy = _working || lib.busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle(
        'Backup & restore',
        'Save everything HomeTunes keeps – music folders, server, playlists, Liked Songs, song edits, covers '
            'and the library – to one file, to restore later or move to another PC or phone.',
      ),
      SwitchListTile(
        title: const Text('Include cover images from music files'),
        subtitle: const Text('Makes the file bigger; without them they\'re re-read from your music. '
            'Covers you chose or found online are always included.'),
        value: _includeCoverCache,
        onChanged: busy ? null : (v) => setState(() => _includeCoverCache = v),
      ),
      if (lib.server.password.isNotEmpty)
        SwitchListTile(
          title: const Text('Include the server password'),
          subtitle: const Text('It\'s stored in the backup file as plain text, so only turn this on if you '
              'keep the file somewhere private.'),
          value: _includePassword,
          onChanged: busy ? null : (v) => setState(() => _includePassword = v),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Export backup…'),
            onPressed: busy ? null : _export,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Import backup…'),
            onPressed: busy ? null : _import,
          ),
        ]),
      ),
    ]);
  }
}
