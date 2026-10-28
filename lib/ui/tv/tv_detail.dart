// The frame of the TV's pages (0.2.0, step 3 of the TV interface; mockup "Album page"): a big
// header (the picture, what it is, the title, a line or two of details and the buttons) and then
// one big row per song, chapter or episode, scrolling up under it. Album, artist, playlist,
// book, series and video collection pages are all made of these (tv_pages.dart,
// tv_book_pages.dart, tv_collection_page.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav.dart';
import '../theme.dart';
import 'tv_browse.dart';
import 'tv_widgets.dart';

/// The hints on a page: what OK and holding OK do on its rows.
const tvPageHints = <TvHint>[('OK', 'Play'), ('Hold OK', 'Options'), ('Back', 'Back')];

/// Sets the hint bubble's words for the tab this page was opened in, while it's the page showing.
class TvPageHintsHere extends StatefulWidget {
  const TvPageHintsHere({super.key, this.hints = tvPageHints, required this.child});
  final List<TvHint> hints;
  final Widget child;

  @override
  State<TvPageHintsHere> createState() => _TvPageHintsHereState();
}

class _TvPageHintsHereState extends State<TvPageHintsHere> {
  // The tab it was opened in (worked out once: the page stays in that tab).
  late final int _tab = Provider.of<AppNav?>(context, listen: false)?.tab ?? 0;

  @override
  Widget build(BuildContext context) => TvPageHints(tab: _tab, hints: widget.hints, child: widget.child);
}

/// A page: [header] at the top, then [items] as rows of [itemHeight], scrolling together.
class TvDetailPage<T> extends StatelessWidget {
  const TvDetailPage({
    super.key,
    required this.header,
    required this.items,
    required this.itemBuilder,
    this.itemHeight = 52,
    this.hints = tvPageHints,
  });

  final Widget header;
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index, FocusNode node) itemBuilder;
  final double itemHeight;
  final List<TvHint> hints;

  @override
  Widget build(BuildContext context) {
    return TvPageHintsHere(
      hints: hints,
      child: Material(
        color: AppColors.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin, TvStyle.topMargin, 20, TvStyle.bottomMargin),
          child: TvAzGrid<T>(
            items: items,
            itemHeight: itemHeight,
            header: header,
            itemBuilder: (context, item, i, node, w) => SizedBox(width: w, child: itemBuilder(context, item, i, node)),
          ),
        ),
      ),
    );
  }
}

/// What a page shows when the thing it's for has gone (renamed, rescanned away).
class TvMissingPage extends StatelessWidget {
  const TvMissingPage({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => TvPageHintsHere(
        hints: const [('Back', 'Back')],
        child: Material(color: AppColors.bg, child: TvEmpty(icon: icon, title: title)),
      );
}

/// The top of a page: [picture] at [pictureWidth] (its shape from [aspectRatio]; round when
/// [round]), then [kind] ("ALBUM"), [title], the [lines] under it, [buttons] in a row, and
/// [below] (a progress bar, a description).
class TvDetailHeader extends StatelessWidget {
  const TvDetailHeader({
    super.key,
    required this.picture,
    required this.kind,
    required this.title,
    this.lines = const [],
    this.buttons = const [],
    this.below,
    this.pictureWidth = 168,
    this.aspectRatio = 1,
    this.round = false,
    this.after,
  });

  final Widget picture;
  final String kind, title;
  final List<String> lines;
  final List<Widget> buttons;
  final Widget? below;
  final double pictureWidth, aspectRatio;
  final bool round;

  /// Under the whole header, before the rows: a row of albums, the season tabs, a heading.
  final Widget? after;

  @override
  Widget build(BuildContext context) {
    final height = pictureWidth / aspectRatio;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(round ? pictureWidth : 14),
            child: SizedBox(width: pictureWidth, height: height, child: picture),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 4),
              Text(kind.toUpperCase(),
                  style: TextStyle(fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600, color: AppColors.textDim)),
              const SizedBox(height: 4),
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 32, height: 1.15, fontWeight: FontWeight.w700, color: Colors.white)),
              for (final l in lines)
                if (l.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
                  ),
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 10, children: buttons),
              ],
              if (below != null) ...[const SizedBox(height: 14), below!],
            ]),
          ),
        ]),
        if (after != null) ...[const SizedBox(height: 18), after!],
      ]),
    );
  }
}

/// A round button with only an icon (the heart, More), named for the remote's screen reader.
class TvIconButton extends StatelessWidget {
  const TvIconButton({super.key, required this.icon, required this.label, required this.onPressed, this.on = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Shown in the accent colour (a favourite).
  final bool on;

  @override
  Widget build(BuildContext context) {
    return TvPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, focused) => TvFocusFrame(
        focused: focused,
        grow: false,
        radius: 999,
        child: Container(
          width: 36,
          height: 36,
          color: focused ? Colors.white : AppColors.surfaceHigh,
          child: Icon(icon, size: 20, color: on ? AppColors.accent : (focused ? const Color(0xFF101114) : AppColors.text)),
        ),
      ),
    );
  }
}

/// A heading between rows ("Disc 2", "Chapters", "Season 1"): not something the remote stops on.
class TvListHeading extends StatelessWidget {
  const TvListHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDim)),
      );
}

/// A short description under a header, folded to a few lines.
class TvDescription extends StatelessWidget {
  const TvDescription(this.text, {super.key, this.lines = 3});
  final String text;
  final int lines;

  @override
  Widget build(BuildContext context) => Text(text.trim(),
      maxLines: lines, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.35, color: AppColors.text.withValues(alpha: 0.85)));
}

/// A thin bar showing how far through something you are.
class TvProgressBar extends StatelessWidget {
  const TvProgressBar(this.value, {super.key, this.width = 320});
  final double value;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 4,
            color: AppColors.accent,
            backgroundColor: const Color(0xFF4A4E57),
          ),
        ),
      );
}
