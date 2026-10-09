// Settings › Servers: adding or editing a server (type, address, user name, password, what it's
// used for, Test), and the question before plain http to the internet. Part of
// server_settings.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../server_settings.dart';

/// Asks before connecting over plain http to a server on the internet (0.1.21, security review
/// #4). True when the user agrees.
Future<bool> askPlainHttp(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect without encryption?'),
        content: const Text(
          'This server didn\'t answer over a secure (https) connection. '
          'HomeTunes can connect over plain http instead, but then your sign-in and what you play '
          'could be read by others on the way.\n\n'
          'Only do this if you trust the network between you and the server. '
          'HomeTunes will remember your answer for this server.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect with http')),
        ],
      ),
    ) ==
    true;

/// Adds a server ([forKind] ticks that kind to start with), or edits [editing].
Future<void> showServerDialog(BuildContext context, ServersModel servers, {ServerEntry? editing, MediaKind? forKind}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ServerDialog(servers: servers, editing: editing, forKind: forKind),
    );

/// The Add a server / Edit server dialog.
class _ServerDialog extends StatefulWidget {
  final ServersModel servers;
  final ServerEntry? editing;
  final MediaKind? forKind;
  const _ServerDialog({required this.servers, this.editing, this.forKind});

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late ServerType _type;
  late final TextEditingController _name, _url, _user, _pass;
  late Set<MediaKind> _uses;
  bool _showPass = false;
  bool _working = false;
  String? _message;
  bool _messageOk = false;

  ServerEntry? get _editing => widget.editing;
  LibraryModel get _lib => widget.servers.library;

  /// Saving makes (or changes) the main music server: a Subsonic server when there isn't one yet,
  /// or the main one being edited.
  bool get _isMain =>
      (_editing?.isMain ?? false) || (_editing == null && _type == ServerType.subsonic && widget.servers.main == null);

  @override
  void initState() {
    super.initState();
    final e = _editing;
    // A new server: the first kind that can hold the section's media (Subsonic for music and
    // audiobooks, Jellyfin for videos).
    _type =
        e?.type ??
        (widget.forKind == null
            ? ServerType.subsonic
            : ServerType.values.firstWhere((t) => t.can.contains(widget.forKind)));
    _name = TextEditingController(text: e?.name ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _user = TextEditingController(text: e?.username ?? '');
    _pass = TextEditingController(text: e != null && e.isMain ? _lib.server.password : '');
    _uses = e == null
        ? _defaultUses(_type)
        : (e.isMain ? {MediaKind.music, if (_lib.serverBooks) MediaKind.audiobooks} : {...e.uses});
    if (e != null && !e.isMain) {
      // The saved password, so it can be shown and kept.
      widget.servers.passwordOf(e).then((p) {
        if (mounted && _pass.text.isEmpty) setState(() => _pass.text = p);
      });
    }
  }

  Set<MediaKind> _defaultUses(ServerType t) =>
      widget.forKind != null && t.can.contains(widget.forKind) ? {widget.forKind!} : {...t.can};

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _say(String text, {required bool ok}) => setState(() {
    _message = text;
    _messageOk = ok;
  });

  Future<void> _test() async {
    setState(() {
      _working = true;
      _message = null;
    });
    final r = await widget.servers.probe(_type, _url.text, username: _user.text.trim(), password: _pass.text);
    if (!mounted) return;
    setState(() => _working = false);
    _say(r.message, ok: r.ok);
  }

  Future<void> _save() async {
    if (_url.text.trim().isEmpty) return _say('Type the server\'s address.', ok: false);
    if (_uses.isEmpty) return _say('Tick at least one thing to use it for.', ok: false);
    setState(() {
      _working = true;
      _message = null;
    });
    final servers = widget.servers;
    String? err;
    if (_isMain) {
      if (_user.text.trim().isEmpty) {
        setState(() => _working = false);
        return _say('Type the user name to sign in with.', ok: false);
      }
      final s = _lib.server;
      final changed = s.url != _url.text.trim() || s.username != _user.text.trim() || s.password != _pass.text;
      if (changed || !s.isComplete) {
        // The password isn't trimmed: spaces could be part of it.
        final config = ServerConfig(url: _url.text.trim(), username: _user.text.trim(), password: _pass.text);
        err = await _lib.connectServer(config);
        if (err == LibraryModel.httpConsentNeeded && mounted) {
          err = await askPlainHttp(context)
              ? await _lib.connectServer(config, allowPlainHttp: true)
              : 'Not connected. Set up https on the server, or connect over your home network or Tailscale.';
        }
      }
      if (err == null) {
        await servers.renameMain(_name.text);
        // Music is always on for the main server (its "Music" chip is fixed); audiobooks follow
        // the chip ("Audiobooks from the music server").
        final main = servers.main;
        if (main != null) await servers.setUse(main, MediaKind.audiobooks, _uses.contains(MediaKind.audiobooks));
      }
    } else if (_editing == null) {
      await servers.add(
        type: _type,
        name: _name.text,
        url: _url.text,
        username: _user.text,
        password: _pass.text,
        uses: _uses,
      );
    } else {
      await servers.update(
        _editing!.copyWith(
          type: _type,
          name: _name.text.trim().isEmpty ? ServerEntry.nameFor(_url.text) : _name.text.trim(),
          url: _url.text.trim(),
          username: _user.text.trim(),
          uses: _uses,
        ),
        password: _pass.text,
      );
    }
    if (!mounted) return;
    setState(() => _working = false);
    if (err != null) return _say(err, ok: false);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editingMain = _editing?.isMain ?? false;
    final willStream = _type.streams && (_isMain);
    return AlertDialog(
      title: Text(_editing == null ? 'Add a server' : 'Edit ${_editing!.name}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<ServerType>(
                key: const ValueKey('server-type'),
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kind of server'),
                items: [
                  for (final t in ServerType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Row(
                        children: [
                          Icon(serverIcon(t), size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(t.label)),
                          if (!t.streams)
                            Text('coming later', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
                        ],
                      ),
                    ),
                ],
                // The main server stays a Subsonic one.
                onChanged: editingMain
                    ? null
                    : (t) => setState(() {
                        _type = t!;
                        _uses = _defaultUses(t);
                        _message = null;
                      }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _type.streams
                      ? (_isMain || editingMain
                            ? '${_type.about} It becomes your main music server: its music (and audiobooks) show in HomeTunes.'
                            : '${_type.about} You already have a main music server; this one is saved, and you can '
                                  'switch to it any time with "Make this the main music server".')
                      : '${_type.about} HomeTunes can\'t play from it yet. Set it up now and it\'s used once that\'s added.',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('server-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name (optional)', hintText: 'e.g. Living room PC'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('server-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(labelText: 'Server address', hintText: 'e.g. ${_type.example}'),
                onChanged: (_) => setState(() {}),
              ),
              // (0.1.17) Plain http outside the home network: the sign-in could be read on the way.
              if (isPlainHttpToInternet(_url.text)) _HttpWarning(tryHttps: !_url.text.trim().startsWith('http://')),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('server-user'),
                controller: _user,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('server-password'),
                controller: _pass,
                obscureText: !_showPass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'Kept in your system\'s protected storage, never in HomeTunes\' files or backups.',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Use it for', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in MediaKind.values)
                    FilterChip(
                      key: ValueKey('server-use-${k.name}'),
                      label: Text(k.label),
                      selected: _uses.contains(k),
                      // The kinds this server can't hold are greyed out; the main server always
                      // gives music.
                      onSelected: !_type.can.contains(k) || ((_isMain || editingMain) && k == MediaKind.music)
                          ? null
                          : (on) => setState(() => on ? _uses.add(k) : _uses.remove(k)),
                    ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _messageOk ? Icons.check_circle_outline : Icons.error_outline,
                        color: _messageOk ? Colors.greenAccent : Colors.redAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_message!, key: const ValueKey('server-message'))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('server-test'),
          onPressed: _working ? null : _test,
          child: const Text('Test connection'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('server-save'),
          onPressed: _working ? null : _save,
          child: _working
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(willStream ? 'Connect' : 'Save'),
        ),
      ],
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    ),
  );
}
