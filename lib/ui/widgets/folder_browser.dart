// Choosing a folder (0.2.0). On a computer and a phone, "Add folder" opens the system's folder
// picker, as before. Google TV has none (Android's own picker isn't there, so the request failed
// and nothing happened: the user, 22 Oct), so on a TV, and anywhere the system picker can't
// open, HomeTunes shows its own: the device's storage and any USB drive, then folder by folder,
// with "Use this folder". It works with a remote: every row is a button.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/device_kind.dart';
import '../../services/storage_volumes.dart';
import '../theme.dart';

/// Lets the user choose a folder. [inApp]: HomeTunes' own browser (default: on an Android TV).
/// [systemPicker] and [roots] stand in for the system picker and the storage list in tests.
Future<String?> pickFolder(
  BuildContext context,
  String title, {
  bool? inApp,
  Future<String?> Function(String title)? systemPicker,
  Future<List<StorageRoot>> Function()? roots,
}) async {
  final own = inApp ?? (Platform.isAndroid && DeviceKind.isTv);
  if (!own) {
    try {
      return await (systemPicker ?? (t) => FilePicker.getDirectoryPath(dialogTitle: t))(title);
    } on PlatformException {
      // No system folder picker here ("explorer_not_found"): use HomeTunes' own below.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Couldn\'t open the folder picker: $e')));
      }
      return null;
    }
  }
  if (!context.mounted) return null;
  return showFolderBrowser(context, title: title, roots: roots);
}

/// HomeTunes' own folder browser. Returns the chosen folder, or null.
Future<String?> showFolderBrowser(BuildContext context,
        {required String title, Future<List<StorageRoot>> Function()? roots}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _FolderBrowser(title: title, roots: roots ?? storageRoots),
    );

class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser({required this.title, required this.roots});
  final String title;
  final Future<List<StorageRoot>> Function() roots;

  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  List<StorageRoot>? _roots;
  StorageRoot? _root; // the storage being browsed (null: choosing one)
  String? _dir; // the folder open now
  List<String> _folders = const [];
  bool _loading = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roots = await widget.roots();
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _loading = false;
    });
    // Only one place to look: straight into it.
    if (roots.length == 1) await _open(roots.single, roots.single.path);
  }

  /// The folders inside [dir] (not hidden ones), A to Z.
  static Future<List<String>> foldersIn(String dir) async {
    final names = <String>[];
    await for (final e in Directory(dir).list(followLinks: false)) {
      if (e is Directory) {
        final name = p.basename(e.path);
        if (!name.startsWith('.')) names.add(name);
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Future<void> _open(StorageRoot root, String dir) async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    List<String> folders;
    String? problem;
    try {
      folders = await foldersIn(dir);
    } catch (_) {
      folders = const [];
      problem = 'This folder can\'t be opened.';
    }
    if (!mounted) return;
    setState(() {
      _root = root;
      _dir = dir;
      _folders = folders;
      _problem = problem;
      _loading = false;
    });
  }

  /// Up one folder; from the top of a storage, back to the list of storage (if there's more
  /// than one).
  void _up() {
    final root = _root, dir = _dir;
    if (root == null || dir == null) return;
    if (p.equals(dir, root.path)) {
      if ((_roots?.length ?? 0) > 1) {
        setState(() {
          _root = null;
          _dir = null;
          _folders = const [];
          _problem = null;
        });
      }
      return;
    }
    _open(root, p.dirname(dir));
  }

  bool get _canGoUp {
    final root = _root, dir = _dir;
    if (root == null || dir == null) return false;
    return !p.equals(dir, root.path) || (_roots?.length ?? 0) > 1;
  }

  /// Where we are, as the user would say it: "SanDisk USB drive › Music › Albums".
  String get _where {
    final root = _root, dir = _dir;
    if (root == null || dir == null) return 'Choose where to look';
    final inside = p.relative(dir, from: root.path);
    return inside == '.' ? root.name : [root.name, ...p.split(inside)].join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final roots = _roots;
    final dir = _dir;
    final rows = <Widget>[
      if (dir == null && roots != null)
        for (final r in roots)
          ListTile(
            key: ValueKey('storage:${r.path}'),
            leading: Icon(r.removable ? Icons.usb : Icons.sd_storage_outlined),
            title: Text(r.name),
            subtitle: Text(r.path, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            onTap: () => _open(r, r.path),
          ),
      if (dir != null && _canGoUp)
        ListTile(
          key: const ValueKey('folder-up'),
          leading: const Icon(Icons.arrow_upward),
          title: Text(p.equals(dir, _root!.path) ? 'Back to the list of storage' : 'Up to ${_upName()}'),
          onTap: _up,
        ),
      if (dir != null && _folders.isEmpty && _problem == null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('No folders inside this one.', style: TextStyle(color: AppColors.textDim)),
        ),
      if (dir != null)
        for (final name in _folders)
          ListTile(
            key: ValueKey('folder:$name'),
            leading: const Icon(Icons.folder_outlined),
            title: Text(name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(_root!, p.join(dir, name)),
          ),
    ];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_where, key: const ValueKey('folder-where'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(child: Text('No storage found.', style: TextStyle(color: AppColors.textDim)))
                    : ListView(children: rows),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(
          key: const ValueKey('folder-use'),
          icon: const Icon(Icons.check),
          label: const Text('Use this folder'),
          onPressed: dir == null || _loading ? null : () => Navigator.of(context).pop(dir),
        ),
      ],
    );
  }

  String _upName() {
    final root = _root!, parent = p.dirname(_dir!);
    return p.equals(parent, root.path) ? root.name : p.basename(parent);
  }
}
