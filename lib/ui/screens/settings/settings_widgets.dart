// Building blocks shared by all the Settings pages.
//
// Every page (library_settings.dart, playback_settings.dart, …) is a [SettingsPageList] of
// [SettingsGroupTitle]s and tiles. Tiles are wrapped in [SettingTarget] so that Settings search
// can jump to them: SettingsScreen puts a [SettingsHighlight] above the page naming the setting
// to show, and the matching SettingTarget scrolls itself into view and glows for a moment.
import 'package:flutter/material.dart';

import '../../theme.dart';

/// The scrolling body of one settings page. [intro] is a short line under the
/// page's title explaining what's on it.
class SettingsPageList extends StatelessWidget {
  final String? intro;
  final List<Widget> children;
  const SettingsPageList({super.key, this.intro, required this.children});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (intro != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(intro!, style: TextStyle(color: AppColors.textDim)),
            ),
          ...children,
        ],
      );
}

/// A small heading that groups settings within a page.
class SettingsGroupTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const SettingsGroupTitle(this.title, [this.subtitle, Key? key]) : super(key: key);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.primary,
              )),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          ],
        ]),
      );
}

/// Which setting a page was opened to show (from search), if any.
class SettingsHighlight extends InheritedWidget {
  /// The [SettingInfo.id] to light up, or null for none.
  final String? id;
  const SettingsHighlight({super.key, required this.id, required super.child});

  /// The id to light up for the page [context] is in (null if none or no highlight above).
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsHighlight>()?.id;

  @override
  bool updateShouldNotify(SettingsHighlight oldWidget) => id != oldWidget.id;
}

/// Marks one setting so search can find it. When the page was opened for this
/// setting, it scrolls into view and briefly lights up.
class SettingTarget extends StatefulWidget {
  final String id;
  final Widget child;
  // The key is made from the id, so each setting's state (and its "done" flag) is kept
  // even if tiles above it appear or disappear.
  SettingTarget(this.id, {required this.child}) : super(key: ValueKey('setting:$id'));

  @override
  State<SettingTarget> createState() => _SettingTargetState();
}

class _SettingTargetState extends State<SettingTarget> {
  bool _lit = false; // currently glowing
  bool _done = false; // already did our scroll-and-glow, so don't repeat it on rebuilds

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || SettingsHighlight.of(context) != widget.id) return;
    _done = true;
    _lit = true;
    // Wait until after this frame so the page is laid out, then scroll this tile about a
    // fifth of the way down the screen, keep it lit for a moment and let it fade out.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Scrollable.ensureVisible(context,
          alignment: 0.2, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        color: _lit ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18) : Colors.transparent,
        // Its own see-through Material so list tiles' hover and tap effects
        // still show above the highlight.
        child: Material(type: MaterialType.transparency, child: widget.child),
      );
}

/// A setting with a few fixed choices, shown as a row with a drop-down.
class ChoiceTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  /// Turns a choice into the text shown for it.
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const ChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // A value saved by an older/newer version that isn't in the list still shows.
    final items = options.contains(value) ? options : [value, ...options];
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [for (final o in items) DropdownMenuItem(value: o, child: Text(label(o)))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
