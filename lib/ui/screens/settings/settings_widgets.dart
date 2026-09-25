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
              child: Text(intro!, style: const TextStyle(color: AppColors.textDim)),
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
            Text(subtitle!, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
          ],
        ]),
      );
}

/// Which setting a page was opened to show (from search), if any.
class SettingsHighlight extends InheritedWidget {
  final String? id;
  const SettingsHighlight({super.key, required this.id, required super.child});

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
  SettingTarget(this.id, {required this.child}) : super(key: ValueKey('setting:$id'));

  @override
  State<SettingTarget> createState() => _SettingTargetState();
}

class _SettingTargetState extends State<SettingTarget> {
  bool _lit = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || SettingsHighlight.of(context) != widget.id) return;
    _done = true;
    _lit = true;
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
        child: widget.child,
      );
}

/// A setting with a few fixed choices, shown as a row with a drop-down.
class ChoiceTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
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
