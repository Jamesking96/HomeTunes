// The TV options panel (0.2.0, the TV interface): on a TV every small menu and right-click
// becomes this. Holding OK on a song, an album, a book or a video slides it in from the right,
// over the dimmed screen, with one big row per action; Back closes it. Step 1 makes the panel;
// step 4 moves each screen's menu into it.
import 'package:flutter/material.dart';

import '../theme.dart';
import 'tv_widgets.dart';

/// One action in the panel.
class TvOption {
  const TvOption(this.label, this.icon, this.onSelected, {this.opensMore = false, this.picture, this.subtitle});
  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  /// A small picture in place of [icon] (a playlist's or an album's cover), and a line under the label.
  final Widget? picture;
  final String? subtitle;

  /// Leads on to another choice (a playlist to add to, a form): shows a chevron.
  final bool opensMore;
}

/// Opens the panel for [title] (with [subtitle] and a small [picture] above the actions). The
/// chosen action runs once the panel has closed.
Future<void> showTvOptions(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? picture,
  required List<TvOption> options,
}) async {
  final chosen = await showGeneralDialog<TvOption>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close the options',
    barrierColor: const Color(0xA8050608),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => _TvOptionsPanel(title: title, subtitle: subtitle, picture: picture, options: options),
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
  chosen?.onSelected();
}

class _TvOptionsPanel extends StatelessWidget {
  const _TvOptionsPanel({required this.title, this.subtitle, this.picture, required this.options});
  final String title;
  final String? subtitle;
  final Widget? picture;
  final List<TvOption> options;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: AppColors.surface,
        elevation: 16,
        child: SizedBox(
          width: 400,
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                if (picture != null) ...[
                  ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 64, height: 64, child: picture)),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: AppColors.textDim)),
                      ),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(children: [
                  for (var i = 0; i < options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TvRow(
                        key: ValueKey('tv-option-${options[i].label}'),
                        title: options[i].label,
                        subtitle: options[i].subtitle,
                        leading: options[i].picture == null
                            ? Icon(options[i].icon)
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(width: 36, height: 36, child: options[i].picture),
                              ),
                        trailing: options[i].opensMore ? const Icon(Icons.chevron_right) : null,
                        height: options[i].subtitle == null && options[i].picture == null ? 44 : 52,
                        autofocus: i == 0,
                        onPressed: () => Navigator.of(context).pop(options[i]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: AppColors.textDim), children: const [
                TextSpan(text: 'Back', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                TextSpan(text: ' closes this panel'),
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}
