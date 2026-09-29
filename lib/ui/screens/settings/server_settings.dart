// Settings › Servers: sign in to a Subsonic-compatible music server (Navidrome etc.) and choose
// whether its music and audiobooks are included.
//
// Connecting, syncing and forgetting are done by LibraryModel (which uses SubsonicClient).
// The lower half is a greyed-out preview of a separate audiobook server (Audiobookshelf), which
// isn't built yet ("phase E" in the roadmap).
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
  // The saved server details the text boxes were last filled from, so we can tell when they
  // change behind our back (see build).
  late ServerConfig _shown;
  bool _connecting = false;
  bool _showPass = false; // the eye button on the password box
  String? _message; // result of the last Connect, shown under the buttons
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

  /// Saves the typed details and tries to connect and sync. Shows either the error or how many
  /// server songs there are now.
  Future<void> _connect() async {
    final lib = context.read<LibraryModel>();
    setState(() {
      _connecting = true;
      _message = null;
    });
    // The password isn't trimmed: spaces could be part of it.
    final config = ServerConfig(url: _url.text.trim(), username: _user.text.trim(), password: _pass.text);
    var err = await lib.connectServer(config);
    if (!mounted) return;
    // 0.1.21 (security review #4): the server didn't answer over https and it's on the internet.
    // Ask once before using plain http; the answer is remembered for this server.
    if (err == LibraryModel.httpConsentNeeded) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connect without encryption?'),
          content: const Text('This server didn\'t answer over a secure (https) connection. '
              'HomeTunes can connect over plain http instead, but then your sign-in and what you play '
              'could be read by others on the way.\n\n'
              'Only do this if you trust the network between you and the server. '
              'HomeTunes will remember your answer for this server.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect with http')),
          ],
        ),
      );
      if (!mounted) return;
      err = ok == true
          ? await lib.connectServer(config, allowPlainHttp: true)
          : 'Not connected. Set up https on the server, or connect over your home network or Tailscale.';
      if (!mounted) return;
    }
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

    // --- Music server ---
    return SettingsPageList(
      intro: 'Optional: stream from your own servers as well as playing your own files.',
      children: [
      const SettingsGroupTitle(
        'Music server',
        'Works with anything that speaks the Subsonic API — Navidrome, Airsonic-Advanced, Gonic, Ampache and others.',
      ),
      // Only once a server is set up (so it isn't in the search catalog).
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
            // Redraw so the plain-http warning below follows what's typed.
            onChanged: (_) => setState(() {}),
          ),
          // (0.1.17) Plain http outside the home network: the login could be read on the way.
          if (isPlainHttpToInternet(_url.text)) _HttpWarning(tryHttps: !_url.text.trim().startsWith('http://')),
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
          // Buttons: Connect / Save & reconnect, Sync now, and Forget server on the right.
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
      // --- Audiobooks: books from the music server, and the future audiobook server ---
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
            borderRadius: AppShape.circular(8),
          ),
          child: Row(children: [
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

/// The warning under the server address when it would use plain http over the internet.
/// [tryHttps]: no scheme was typed, so HomeTunes will try https:// first anyway.
class _HttpWarning extends StatelessWidget {
  final bool tryHttps;
  const _HttpWarning({this.tryHttps = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lock_open, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tryHttps
                  ? 'HomeTunes will try a secure (https) connection first. If the server only offers '
                      'http, it will ask before using it, because your sign-in could be read by others on the way.'
                  : 'This address isn\'t secure (http). Outside your home network your sign-in could be '
                      'read by others on the way. Use https:// if your server supports it.',
              style: const TextStyle(fontSize: 12, color: Colors.amber),
            ),
          ),
        ]),
      );
}

