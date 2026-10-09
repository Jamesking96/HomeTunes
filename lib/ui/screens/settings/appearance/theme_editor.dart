// Appearance › Advanced: the theme editor (every colour, with a live preview and readability
// warnings). Part of appearance_settings.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../appearance_settings.dart';

/// Opens the full theme editor for [start]; saving it switches to it.
Future<void> openThemeEditor(BuildContext context, AppPalette start) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThemeEditor(start: start)));

/// Settings › Appearance › Advanced: every colour of one saved theme, with a live preview and
/// warnings when colours are hard to tell apart.
class ThemeEditor extends StatefulWidget {
  final AppPalette start;
  const ThemeEditor({super.key, required this.start});

  /// The colours, in the order they're listed, with plain names and what each one colours.
  static final slots = <(String, String, Color Function(AppPalette), AppPalette Function(AppPalette, Color))>[
    ('Background', 'Pages', (p) => p.bg, (p, c) => p.copyWith(bg: c)),
    ('Panels', 'The player bar, tab bar and cards', (p) => p.surface, (p, c) => p.copyWith(surface: c)),
    ('Raised panels', 'Menus, pop-ups and hovered items', (p) => p.surfaceHigh, (p, c) => p.copyWith(surfaceHigh: c)),
    ('Text', 'Titles, song names and icons', (p) => p.text, (p, c) => p.copyWith(text: c)),
    ('Grey text', 'Artists, times and other smaller details', (p) => p.textDim, (p, c) => p.copyWith(textDim: c)),
    ('Highlight', 'Selected items, switches, heart and progress', (p) => p.accent, (p, c) => p.copyWith(accent: c)),
    ('Slider track', 'The unplayed part of the seek and volume bars', (p) => p.track, (p, c) => p.copyWith(track: c)),
    ('Play button', 'The big round play button', (p) => p.playButton, (p, c) => p.copyWith(playButton: c)),
  ];

  @override
  State<ThemeEditor> createState() => _ThemeEditorState();
}

class _ThemeEditorState extends State<ThemeEditor> {
  late AppPalette _p = widget.start;
  late final _name = TextEditingController(text: widget.start.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim().isEmpty ? 'My theme' : _name.text.trim();
    // The theme changes at once; writing settings.json carries on in the background.
    context.read<LibraryModel>().saveTheme(_p.copyWith(name: name).toJson());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final problems = _p.readabilityProblems();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit theme'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(key: const ValueKey('save-theme'), onPressed: _save, child: const Text('Save and use')),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                key: const ValueKey('theme-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              ThemePreview(palette: _p, height: 180),
              const SizedBox(height: 8),
              if (problems.isEmpty)
                Row(children: [
                  const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Everything is easy to read.', style: TextStyle(color: AppColors.textDim)),
                ])
              else
                Container(
                  key: const ValueKey('theme-problems'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: AppShape.circular(8),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Some things may be hard to read', style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    for (final m in problems) Text('• $m'),
                    const SizedBox(height: 4),
                    Text('You can still save it.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ]),
                ),
              const SizedBox(height: 8),
              for (final s in ThemeEditor.slots)
                ListTile(
                  key: ValueKey('slot:${s.$1}'),
                  contentPadding: EdgeInsets.zero,
                  leading: _Swatch(colour: s.$3(_p), size: 32),
                  title: Text(s.$1),
                  subtitle: Text('${s.$2} · ${colourToHex(s.$3(_p))}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final c = await showColourPicker(context, title: s.$1, initial: s.$3(_p), mode: PickerMode.any);
                    if (c != null) setState(() => _p = s.$4(_p, c));
                  },
                ),
              // Delete, for a theme that's already saved (not a new one that hasn't been yet).
              if (context.select<LibraryModel, bool>((l) => l.savedThemes.any((t) => t['id'] == widget.start.id))) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('editor-delete'),
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete this theme'),
                    onPressed: () async {
                      if (await confirmDeleteTheme(context, widget.start) && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
