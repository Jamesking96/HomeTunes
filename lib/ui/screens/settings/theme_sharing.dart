// Sharing themes with friends (0.1.29): Settings › Appearance › a saved theme's ⋮ › Share…
// (and "Share these colours" under Your own) shows a theme code to copy into a message, or
// saves a .hometunes-theme file. "Import a theme" takes either one back: paste the code (or the
// whole message it came in), or open the file. The theme is added to Advanced and used.
//
// What's shared is only the theme's name and its eight colours; nothing about the library or
// the person. The code is "HOMETUNES-THEME:" and the same JSON as the file, base64url-encoded
// so chat apps don't break it up. Anything read back is checked: the text is size-limited,
// every colour must be a #RRGGBB code, and the name is tidied and shortened.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import '../../theme.dart';
import 'appearance_settings.dart';

/// File extension for a shared theme.
const themeFileExtension = 'hometunes-theme';

/// What a theme code starts with.
const themeCodePrefix = 'HOMETUNES-THEME:';

/// The version of the shared-theme format this HomeTunes writes and reads.
const themeFormatVersion = 1;

/// Longest text or file accepted as a shared theme (a real one is well under 1 KB).
const maxSharedThemeLength = 64 * 1024;

/// Longest theme name kept from a shared theme.
const maxThemeNameLength = 40;

/// The shared form of [p]: its name and colours (not its id, which is only for this device).
Map<String, dynamic> sharedThemeJson(AppPalette p) {
  final j = p.toJson()..remove('id');
  return {'hometunesTheme': themeFormatVersion, ...j};
}

/// The contents of a .hometunes-theme file: readable JSON.
String themeFileText(AppPalette p) => '${const JsonEncoder.withIndent('  ').convert(sharedThemeJson(p))}\n';

/// A one-line code for [p] to paste into a message.
String themeCode(AppPalette p) =>
    themeCodePrefix + base64Url.encode(utf8.encode(jsonEncode(sharedThemeJson(p)))).replaceAll('=', '');

/// A suggested file name for [p], e.g. "Sunset.hometunes-theme".
String themeFileName(AppPalette p) {
  final safe = p.name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').trim();
  return '${safe.isEmpty ? 'HomeTunes theme' : safe}.$themeFileExtension';
}

/// Reads a shared theme from a pasted code (on its own or inside a longer message) or a
/// theme file's text. The result has a placeholder id; [addSharedTheme] gives it a real one.
/// Throws a [FormatException] whose message is written for the user.
AppPalette readSharedTheme(String text) {
  if (text.length > maxSharedThemeLength) {
    throw const FormatException('That\'s far too long to be a HomeTunes theme.');
  }
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw const FormatException('Paste a theme code first.');

  Object? json;
  final code = RegExp('${RegExp.escape(themeCodePrefix)}\\s*([A-Za-z0-9_-]+)', caseSensitive: false)
      .firstMatch(trimmed);
  if (code != null) {
    var b = code.group(1)!;
    b = b.padRight(b.length + (4 - b.length % 4) % 4, '=');
    try {
      json = jsonDecode(utf8.decode(base64Url.decode(b)));
    } catch (_) {
      throw const FormatException('That theme code is incomplete. Copy the whole code and try again.');
    }
  } else if (trimmed.startsWith('{')) {
    try {
      json = jsonDecode(trimmed);
    } catch (_) {
      throw const FormatException('That isn\'t a HomeTunes theme.');
    }
  } else {
    throw FormatException('That isn\'t a HomeTunes theme code. Theme codes start with $themeCodePrefix');
  }
  if (json is! Map) throw const FormatException('That isn\'t a HomeTunes theme.');

  final version = json['hometunesTheme'];
  final name = _tidyName(json['name']);
  final p = AppPalette.fromJson({...json, 'id': 'shared', 'name': name});
  if (p == null) {
    if (version is int && version > themeFormatVersion) {
      throw const FormatException('This theme was made by a newer version of HomeTunes. Update HomeTunes and try again.');
    }
    throw const FormatException('This theme is missing some of its colours, so it can\'t be used.');
  }
  return p;
}

/// A shared name made safe to show: control characters removed, spaces tidied, shortened.
String _tidyName(Object? raw) {
  var n = raw is String ? raw : '';
  n = n.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (n.length > maxThemeNameLength) n = n.substring(0, maxThemeNameLength).trimRight();
  return n.isEmpty ? 'Shared theme' : n;
}

/// Colours only, for spotting a theme that's already here.
String _colourKey(AppPalette p) => [for (final f in AppPalette.colourSlots.values) colourToHex(f(p))].join();

/// A saved theme with exactly [p]'s colours, if there is one.
AppPalette? sameSavedTheme(LibraryModel lib, AppPalette p) {
  final key = _colourKey(p);
  for (final s in savedPalettes(lib)) {
    if (_colourKey(s) == key) return s;
  }
  return null;
}

/// [name], or "name (2)", "name (3)"… so it doesn't match one of [taken].
String uniqueThemeName(String name, Iterable<String> taken) {
  final lower = {for (final t in taken) t.toLowerCase()};
  if (!lower.contains(name.toLowerCase())) return name;
  for (var i = 2;; i++) {
    final n = '$name ($i)';
    if (!lower.contains(n.toLowerCase())) return n;
  }
}

/// Adds a shared theme to Advanced (with a new id, and a name that isn't already used) and
/// uses it. If a saved theme already has exactly these colours, that one is used instead.
/// Returns the theme now in use and whether it was newly added.
Future<(AppPalette, bool)> addSharedTheme(LibraryModel lib, AppPalette p) async {
  final existing = sameSavedTheme(lib, p);
  if (existing != null) {
    await lib.setTheme(id: existing.id);
    return (existing, false);
  }
  final added = p.copyWith(id: newThemeId(), name: uniqueThemeName(p.name, savedPalettes(lib).map((t) => t.name)));
  await lib.saveTheme(added.toJson());
  return (added, true);
}

/// Share… : the theme code to copy, or save it as a file.
Future<void> showShareTheme(BuildContext context, AppPalette p) {
  // "Your own" is shared with a name a friend can recognise.
  final theme = p.id == 'custom' ? p.copyWith(name: 'My colours') : p;
  return showDialog<void>(context: context, builder: (_) => _ShareThemeDialog(theme: theme));
}

class _ShareThemeDialog extends StatelessWidget {
  final AppPalette theme;
  const _ShareThemeDialog({required this.theme});

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: themeCode(theme)));
    if (context.mounted) Navigator.of(context).pop();
    messenger?.showSnackBar(const SnackBar(content: Text('Theme code copied. Paste it into a message to a friend.')));
  }

  Future<void> _save(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await FilePicker.saveFile(
        fileName: themeFileName(theme),
        bytes: Uint8List.fromList(utf8.encode(themeFileText(theme))),
        dialogTitle: 'Save theme',
      );
      if (saved == null) return; // cancelled
      if (context.mounted) Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text('"${theme.name}" saved as a theme file')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t save the theme file: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: AppColors.textDim, fontSize: 13);
    return AlertDialog(
      key: const ValueKey('share-theme-dialog'),
      title: Text('Share "${theme.name}"'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ThemePreview(palette: theme, height: 110),
            const SizedBox(height: 12),
            Text('Send your friend this theme code, or save it as a file and send that. In HomeTunes '
                'they go to Settings › Appearance › Import a theme.', style: dim),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: AppShape.circular(8),
              ),
              child: SelectableText(
                themeCode(theme),
                key: const ValueKey('theme-code'),
                // Consolas on Windows, the system's fixed-width font on the phone, else the normal one.
                style: const TextStyle(
                    fontFamily: 'Consolas', fontFamilyFallback: ['Menlo', 'monospace', 'Roboto'], fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            Text('Only the name and colours are shared.', style: dim.copyWith(fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        OutlinedButton.icon(
          key: const ValueKey('save-theme-file'),
          icon: const Icon(Icons.save_alt, size: 18),
          label: const Text('Save as file…'),
          onPressed: () => _save(context),
        ),
        FilledButton.icon(
          key: const ValueKey('copy-theme-code'),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy code'),
          onPressed: () => _copy(context),
        ),
      ],
    );
  }
}

/// Import a theme: paste a code or open a file, see it, then add it.
Future<void> showImportTheme(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const ImportThemeDialog());

class ImportThemeDialog extends StatefulWidget {
  const ImportThemeDialog({super.key});

  @override
  State<ImportThemeDialog> createState() => _ImportThemeDialogState();
}

class _ImportThemeDialogState extends State<ImportThemeDialog> {
  final _text = TextEditingController();
  String? _error;

  /// The theme read, once there is one: the dialog then shows it with "Add and use".
  AppPalette? _found;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _read(String text) {
    try {
      final p = readSharedTheme(text);
      setState(() {
        _found = p;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text ?? '';
    if (!mounted) return;
    if (t.trim().isEmpty) {
      setState(() => _error = 'There\'s nothing to paste. Copy the theme code first.');
      return;
    }
    _text.text = t.trim();
    _read(t);
  }

  Future<void> _openFile() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose a HomeTunes theme file');
      final path = file?.path;
      if (path == null || !mounted) return;
      final f = File(path);
      if (await f.length() > maxSharedThemeLength) {
        setState(() => _error = 'That file is far too big to be a HomeTunes theme.');
        return;
      }
      _read(utf8.decode(await f.readAsBytes(), allowMalformed: true));
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t open that file: $e');
    }
  }

  Future<void> _add() async {
    final p = _found;
    if (p == null) return;
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();
    final (used, added) = await addSharedTheme(lib, p);
    messenger?.showSnackBar(SnackBar(
      content: Text(added
          ? '"${used.name}" added to your themes and now in use'
          : 'You already had this theme ("${used.name}"), so it\'s now in use'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: AppColors.textDim, fontSize: 13);
    final found = _found;

    if (found != null) {
      final problems = found.readabilityProblems();
      return AlertDialog(
        key: const ValueKey('import-theme-preview'),
        title: Text('Add "${found.name}"?'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ThemePreview(palette: found, height: 150),
              const SizedBox(height: 10),
              Text(
                problems.isEmpty
                    ? 'It\'s added to your themes under Advanced, where you can change it or delete it later.'
                    : 'Some things in this theme may be hard to read. You can change its colours later under '
                        'Advanced.',
                style: dim,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => setState(() => _found = null), child: const Text('Back')),
          FilledButton(key: const ValueKey('add-imported-theme'), onPressed: _add, child: const Text('Add and use')),
        ],
      );
    }

    return AlertDialog(
      key: const ValueKey('import-theme-dialog'),
      title: const Text('Import a theme'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Paste a theme code a friend sent you (it starts with $themeCodePrefix), or open a theme file.',
                style: dim),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('import-theme-code'),
              controller: _text,
              minLines: 2,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [LengthLimitingTextInputFormatter(maxSharedThemeLength)],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Theme code',
                errorText: _error,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  key: const ValueKey('paste-theme-code'),
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        OutlinedButton.icon(
          key: const ValueKey('open-theme-file'),
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('Open a file…'),
          onPressed: _openFile,
        ),
        FilledButton(
          key: const ValueKey('read-theme-code'),
          onPressed: () => _read(_text.text),
          child: const Text('Next'),
        ),
      ],
    );
  }
}
