import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:provider/provider.dart';

import '../../services/subsonic_client.dart';
import '../../state/library_model.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [_FoldersSection(), Divider(height: 32), _ServerSection()],
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
    ]);
  }
}

// ---------------------------------------------------------------- server

class _ServerSection extends StatefulWidget {
  const _ServerSection();

  @override
  State<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends State<_ServerSection> {
  late final TextEditingController _url, _user, _pass;
  bool _connecting = false;
  bool _showPass = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<LibraryModel>().server;
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
