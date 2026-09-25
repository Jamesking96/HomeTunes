import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/subsonic_client.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Servers: the music server, and where audiobooks can stream from.
class ServerSettings extends StatefulWidget {
  const ServerSettings({super.key});

  @override
  State<ServerSettings> createState() => ServerSettingsState();
}

class ServerSettingsState extends State<ServerSettings> {
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

    return SettingsPageList(
      intro: 'Optional: stream from your own servers as well as playing your own files.',
      children: [
      const SettingsGroupTitle(
        'Music server',
        'Works with anything that speaks the Subsonic API — Navidrome, Airsonic-Advanced, Gonic, Ampache and others.',
      ),
      if (hasServer)
        SwitchListTile(
          title: const Text('Include server music'),
          subtitle: Text(lib.serverEnabled ? '$remoteCount songs from ${lib.server.url}' : 'Local files only'),
          value: lib.serverEnabled,
          onChanged: lib.busy ? null : lib.setServerEnabled,
        ),
      SettingTarget('server', child: Padding(
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
      )),
      const SettingsGroupTitle('Audiobooks'),
      SettingTarget(
        'server-books',
        child: SwitchListTile(
          title: const Text('Audiobooks from the music server'),
          subtitle: Text(hasServer
              ? 'Books on your music server show in the Books tab, the same way as books in your folders. '
                  'Turn off to keep them out.'
              : 'Once a music server is connected, books on it show in the Books tab. Turn off to keep them out.'),
          value: lib.serverBooks,
          onChanged: lib.setServerBooks,
        ),
      ),
      SettingTarget(
        'book-server',
        child: const _AudiobookServerPreview(),
      ),
      ],
    );
  }
}

/// Where a separate audiobook server (Audiobookshelf) will be set up. Shown
/// greyed out until that connection is built.
class _AudiobookServerPreview extends StatelessWidget {
  const _AudiobookServerPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Audiobook server', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(children: [
            Icon(Icons.schedule, size: 18, color: AppColors.textDim),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Coming in a later update: stream audiobooks from a separate server such as Audiobookshelf, '
                'with your place in each book kept in step. These boxes will work then.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const TextField(
          enabled: false,
          decoration: InputDecoration(labelText: 'Server type', hintText: 'Audiobookshelf'),
        ),
        const SizedBox(height: 8),
        const TextField(
          enabled: false,
          decoration: InputDecoration(labelText: 'Server address', hintText: 'e.g. http://192.168.1.20:13378'),
        ),
        const SizedBox(height: 8),
        const TextField(enabled: false, decoration: InputDecoration(labelText: 'Username')),
        const SizedBox(height: 8),
        const TextField(enabled: false, decoration: InputDecoration(labelText: 'Password')),
        const SizedBox(height: 16),
        const FilledButton(onPressed: null, child: Text('Connect')),
      ]),
    );
  }
}
