// Settings › Appearance: pick the colour theme — Default, Midnight, Forest, "Your own" (a
// highlight and a background colour, 0.1.24) — and, under Advanced (0.1.25), make any number of
// saved themes where every colour is chosen (light themes too), and set the text size and how
// rounded corners are.
//
// Everything is saved in settings.json by LibraryModel (so it's in backups). HomeTunesApp
// (main.dart) turns the settings into an [AppLook] with [lookOfSettings], applies the text size
// with [withTextSize], and [RedrawOnThemeChange] redraws every screen when the look changes,
// because many widgets read AppColors / AppShape directly rather than through the Material theme.
//
// 0.1.29: the colour picker has a box to type or paste a colour code (#FF7A59), and saved themes
// can be shared: Share… on a theme gives a theme code to copy or a .hometunes-theme file, and
// Import a theme reads either one back (theme_sharing.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';
import 'theme_sharing.dart';
import 'video_player_look_settings.dart';

import 'appearance/colour_picker.dart';
export 'appearance/colour_picker.dart' show accentSuggestions, backgroundSuggestions, anySuggestions, PickerMode, showColourPicker;
part 'appearance/theme_editor.dart';

/// Everything Settings › Appearance changes.
typedef AppLook = ({AppPalette palette, double corners, double textSize});

/// The user's saved themes (Advanced); damaged entries are skipped.
List<AppPalette> savedPalettes(LibraryModel lib) =>
    [for (final t in lib.savedThemes) ?AppPalette.fromJson(t)];

/// The theme the saved settings ask for.
AppPalette paletteOfSettings(LibraryModel lib) => paletteFor(
      lib.themeId,
      customAccent: colourFromHex(lib.customAccent) ?? defaultPalette.accent,
      customBackground: colourFromHex(lib.customBackground) ?? defaultPalette.bg,
      saved: savedPalettes(lib),
    );

/// The whole look the saved settings ask for.
AppLook lookOfSettings(LibraryModel lib) =>
    (palette: paletteOfSettings(lib), corners: lib.cornerRoundness, textSize: lib.textSize);

/// Applies the chosen text size on top of the system's own text size setting.
Widget withTextSize(BuildContext context, double size, Widget child) {
  if (size == 1.0) return child;
  final mq = MediaQuery.of(context);
  final system = mq.textScaler.scale(14) / 14;
  return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(system * size)), child: child);
}

/// Redraws the whole app after the look changes. Widgets that read AppColors / AppShape
/// (rather than Theme.of) wouldn't otherwise notice, so every element is marked to build again.
class RedrawOnThemeChange extends StatefulWidget {
  final Object look;
  final Widget child;
  const RedrawOnThemeChange({super.key, required this.look, required this.child});

  @override
  State<RedrawOnThemeChange> createState() => _RedrawOnThemeChangeState();
}

class _RedrawOnThemeChangeState extends State<RedrawOnThemeChange> {
  @override
  void didUpdateWidget(RedrawOnThemeChange old) {
    super.didUpdateWidget(old);
    if (old.look == widget.look) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A light starting point for a new theme (Advanced › New theme › Light).
const lightStarter = AppPalette(
  id: 'saved:new',
  name: 'Daylight',
  accent: Color(0xFF2F6FEB),
  bg: Color(0xFFF5F6F8),
  surface: Color(0xFFFFFFFF),
  surfaceHigh: Color(0xFFE9EBEF),
  text: Color(0xFF15171C),
  textDim: Color(0xFF5B6270),
  track: Color(0xFFC9CDD4),
  playButton: Color(0xFF15171C),
);

/// Settings › Appearance.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final accent = colourFromHex(lib.customAccent) ?? defaultPalette.accent;
    final background = colourFromHex(lib.customBackground) ?? defaultPalette.bg;
    final custom = AppPalette.fromColours(accent: accent, background: background);
    final saved = savedPalettes(lib);
    final chosen = paletteOfSettings(lib).id == 'default' && lib.themeId != 'default' ? 'default' : lib.themeId;

    return SettingsPageList(children: [
      const SettingsGroupTitle('Colour theme'),
      SettingTarget(
        'theme',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final p in [...builtInPalettes, custom, ...saved])
              ThemeCard(
                palette: p,
                selected: p.id == chosen,
                onTap: () => lib.setTheme(id: p.id),
              ),
          ]),
        ),
      ),
      SettingTarget(
        'theme-custom',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SettingsGroupTitle('Your own colours'),
          ListTile(
            leading: _Swatch(colour: custom.accent),
            title: const Text('Highlight colour'),
            subtitle: const Text('Buttons, the selected tab, switches and progress'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final c = await showColourPicker(context, title: 'Highlight colour', initial: custom.accent);
              if (c != null) await lib.setTheme(id: 'custom', accent: colourToHex(c));
            },
          ),
          ListTile(
            leading: _Swatch(colour: custom.bg),
            title: const Text('Background colour'),
            subtitle: const Text('Pages and panels (panels are made a little lighter automatically)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final c = await showColourPicker(context,
                  title: 'Background colour', initial: custom.bg, mode: PickerMode.darkBackground);
              if (c != null) await lib.setTheme(id: 'custom', background: colourToHex(c));
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Choosing a colour here switches to "Your own". Backgrounds stay dark and highlights stay '
              'bright, so text is always easy to read. For full control, use Advanced below.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
          // Back to the colours "Your own" starts with (0.1.25). Only when something was chosen.
          // Share sends these colours as a theme (0.1.29).
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
            child: Wrap(spacing: 4, children: [
              TextButton.icon(
                key: const ValueKey('share-custom'),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share these colours'),
                onPressed: () => showShareTheme(context, custom),
              ),
              TextButton.icon(
              key: const ValueKey('reset-custom'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset to default colours'),
              onPressed: lib.customAccent == null && lib.customBackground == null
                  ? null
                  : () {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      final before = (lib.customAccent, lib.customBackground);
                      lib.resetCustomColours(); // the screen changes at once; the file save carries on
                      messenger
                        ?..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: const Text('"Your own" is back to its default colours'),
                          action: SnackBarAction(label: 'Undo', onPressed: () => lib.restoreCustomColours(before)),
                        ));
                    },
              ),
            ]),
          ),
        ]),
      ),
      const SettingsGroupTitle('Advanced', 'Choose every colour yourself, and change text size and corners'),
      SettingTarget(
        'theme-advanced',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in saved)
            ListTile(
              key: ValueKey('saved-theme:${p.id}'),
              leading: _Strip(palette: p),
              title: Text(p.name),
              subtitle: Text(p.id == lib.themeId ? 'In use' : (p.isLight ? 'Light theme' : 'Dark theme')),
              onTap: () => lib.setTheme(id: p.id),
              // Edit and Delete are buttons you can see; Duplicate (and both again) are in ⋮.
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  key: ValueKey('edit-theme:${p.id}'),
                  tooltip: 'Edit theme',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => openThemeEditor(context, p),
                ),
                IconButton(
                  key: ValueKey('delete-theme:${p.id}'),
                  tooltip: 'Delete theme',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => confirmDeleteTheme(context, p),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (a) async {
                    switch (a) {
                      case 'edit':
                        await openThemeEditor(context, p);
                      case 'copy':
                        await openThemeEditor(context, p.copyWith(id: newThemeId(), name: '${p.name} copy'));
                      case 'share':
                        await showShareTheme(context, p);
                      case 'delete':
                        await confirmDeleteTheme(context, p);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit…')),
                    PopupMenuItem(value: 'copy', child: Text('Duplicate…')),
                    PopupMenuItem(key: ValueKey('menu-share-theme'), value: 'share', child: Text('Share…')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                key: const ValueKey('new-theme'),
                icon: const Icon(Icons.add),
                label: const Text('New theme from the current one'),
                onPressed: () => openThemeEditor(
                    context, AppColors.current.copyWith(id: newThemeId(), name: 'My theme')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('new-light-theme'),
                icon: const Icon(Icons.light_mode_outlined),
                label: const Text('New light theme'),
                onPressed: () => openThemeEditor(context, lightStarter.copyWith(id: newThemeId())),
              ),
              // A theme a friend shared: a theme code or a .hometunes-theme file (0.1.29).
              OutlinedButton.icon(
                key: const ValueKey('import-theme'),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Import a theme'),
                onPressed: () => showImportTheme(context),
              ),
            ]),
          ),
        ]),
      ),
      SettingTarget(
        'text-size',
        child: ChoiceTile<double>(
          title: 'Text size',
          subtitle: 'On top of your device\'s own text size setting',
          value: lib.textSize,
          options: [for (final t in textSizes) t.$2],
          label: (v) => textSizes.firstWhere((t) => t.$2 == v, orElse: () => ('${(v * 100).round()}%', v)).$1,
          onChanged: (v) => lib.setLook(textSize: v),
        ),
      ),
      SettingTarget(
        'corners',
        child: ChoiceTile<double>(
          title: 'Corners',
          subtitle: 'How rounded covers, cards, buttons and pop-ups are',
          value: lib.cornerRoundness,
          options: [for (final t in roundnessChoices) t.$2],
          label: (v) => roundnessChoices.firstWhere((t) => t.$2 == v, orElse: () => ('${(v * 100).round()}%', v)).$1,
          onChanged: (v) => lib.setLook(cornerRoundness: v),
        ),
      ),
      // Shrink to fit small windows (0.1.41; widgets/window_scale.dart).
      SettingTarget(
        'scale-with-window',
        child: SwitchListTile(
          key: const ValueKey('scale-with-window'),
          title: const Text('Shrink to fit small windows'),
          subtitle: const Text('On a computer, buttons, text and pictures get a little smaller when you make the '
              'window small, so more fits. Turn off to keep them the same size.'),
          value: lib.scaleWithWindow,
          onChanged: lib.setScaleWithWindow,
        ),
      ),
      // The video player's buttons: colour, size, backing and progress bar (0.1.40).
      const VideoPlayerLookSettings(),
      const SizedBox(height: 16),
    ]);
  }
}

/// Asks, then deletes a saved theme. Returns true if it was deleted.
Future<bool> confirmDeleteTheme(BuildContext context, AppPalette p) async {
  final lib = context.read<LibraryModel>();
  final inUse = lib.themeId == p.id;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete "${p.name}"?'),
      content: Text(inUse
          ? 'This theme is in use, so HomeTunes goes back to Default. This can\'t be undone.'
          : 'The theme is removed. This can\'t be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('confirm-delete'), onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true) return false;
  lib.deleteTheme(p.id); // the screen changes at once; the file save carries on
  return true;
}

/// A fresh id for a saved theme.
String newThemeId() => 'saved:${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// A small preview of a theme: a page with a panel along the bottom, two lines of text and a
/// play button in its highlight colour. Tap to use it.
class ThemeCard extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;
  final double width;
  const ThemeCard({super.key, required this.palette, required this.selected, required this.onTap, this.width = 150});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final ring = selected ? AppColors.accent : AppColors.textDim.withValues(alpha: 0.4);
    return Semantics(
      button: true,
      selected: selected,
      label: '${p.name} theme',
      child: InkWell(
        key: ValueKey('theme:${p.id}'),
        borderRadius: AppShape.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ThemePreview(palette: p, height: width * 2 / 3, border: Border.all(color: ring, width: selected ? 2.5 : 1)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (selected) Icon(Icons.check_circle, size: 18, color: AppColors.accent),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The little picture of a theme used on the cards and in the editor.
class ThemePreview extends StatelessWidget {
  final AppPalette palette;
  final double height;
  final BoxBorder? border;
  const ThemePreview({super.key, required this.palette, this.height = 100, this.border});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final k = height / 100;
    BoxDecoration bar(Color c) => BoxDecoration(color: c, borderRadius: AppShape.circular(4 * k));
    return Container(
      height: height,
      decoration: BoxDecoration(color: p.bg, borderRadius: AppShape.circular(12), border: border),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12 * k, 12 * k, 12 * k, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 70 * k, height: 8 * k, decoration: bar(p.text)),
                  SizedBox(height: 6 * k),
                  Container(width: 48 * k, height: 6 * k, decoration: bar(p.textDim)),
                ]),
              ),
              // A raised panel (menus, dialogs) with a highlight dot.
              Container(
                width: 34 * k,
                height: 26 * k,
                decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: AppShape.circular(4 * k)),
                alignment: Alignment.center,
                child: Container(width: 8 * k, height: 8 * k, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
              ),
            ]),
          ),
        ),
        Container(
          height: 34 * k,
          color: p.surface,
          padding: EdgeInsets.symmetric(horizontal: 10 * k),
          child: Row(children: [
            Container(
                width: 18 * k,
                height: 18 * k,
                decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: AppShape.circular(3 * k))),
            SizedBox(width: 8 * k),
            Expanded(
              child: Stack(alignment: Alignment.centerLeft, children: [
                Container(height: 3 * k, decoration: bar(p.track)),
                FractionallySizedBox(widthFactor: 0.4, child: Container(height: 3 * k, decoration: bar(p.text))),
              ]),
            ),
            SizedBox(width: 8 * k),
            Container(
              width: 20 * k,
              height: 20 * k,
              decoration: BoxDecoration(color: p.playButton, shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, size: 14 * k, color: p.onPlay),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color colour;
  final double size;
  const _Swatch({required this.colour, this.size = 28});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: colour, shape: BoxShape.circle, border: Border.all(color: AppColors.textDim.withValues(alpha: 0.6))),
      );
}

/// A saved theme's main colours side by side (list rows).
class _Strip extends StatelessWidget {
  final AppPalette palette;
  const _Strip({required this.palette});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: AppShape.circular(6),
        child: SizedBox(
          width: 48,
          height: 28,
          // Stretch: an empty ColoredBox would otherwise be 0 high.
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final c in [palette.bg, palette.surface, palette.text, palette.accent])
              Expanded(child: ColoredBox(color: c)),
          ]),
        ),
      );
}
