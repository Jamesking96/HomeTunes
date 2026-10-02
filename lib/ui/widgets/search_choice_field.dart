// A drop-down with a search box at the top (0.1.49, the user asked: "When filtering by
// something, the selection drop downs can get rather large, add a dedicated search bar at the
// top of each one").
//
// Used by every "Show only" filter sheet (Your Library's Artists / Albums / Songs, Books and
// Videos). It looks like the old dropdown field (label, current choice, arrow); a tap opens a
// list under it with a Search box first, then "All" and each choice with its count. Typing
// narrows the list (every word must appear, any order, ignoring case); Enter picks the first
// match; Esc or a tap outside closes it without changing anything.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../theme.dart';

/// True when [text] contains every word of [query] (ignoring case). An empty query matches all.
bool choiceMatches(String text, String query) {
  final t = text.toLowerCase();
  return query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(t.contains);
}

class SearchChoiceField extends StatelessWidget {
  const SearchChoiceField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;

  /// The current choice; null means All.
  final String? value;

  /// Each choice and how many items it has, in the order to show them.
  final Map<String, int> options;
  final ValueChanged<String?> onChanged;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // On the outer navigator, which covers the whole window, so the field's window position
    // lines up with where the list is drawn.
    final picked = await Navigator.of(context, rootNavigator: true).push<_Pick>(_ChoiceRoute(
      anchor: rect,
      label: label,
      value: value,
      options: options,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ));
    if (picked != null && picked.value != value) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final shown = value == null ? 'All' : '$value  (${options[value] ?? 0})';
    return InkWell(
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// What was picked (wrapped so "All", which is null, can be told apart from "closed").
class _Pick {
  final String? value;
  const _Pick(this.value);
}

/// The open list, laid out under the field (or above it when there's no room below).
class _ChoiceRoute extends PopupRoute<_Pick> {
  _ChoiceRoute({
    required this.anchor,
    required this.label,
    required this.value,
    required this.options,
    required this.barrierLabel,
  });

  final Rect anchor;
  final String label;
  final String? value;
  final Map<String, int> options;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return FadeTransition(
      opacity: animation,
      child: CustomSingleChildLayout(
        delegate: _Below(anchor, MediaQuery.paddingOf(context) + MediaQuery.viewInsetsOf(context)),
        child: _ChoiceList(label: label, value: value, options: options),
      ),
    );
  }
}

class _Below extends SingleChildLayoutDelegate {
  _Below(this.anchor, this.padding);
  final Rect anchor;
  final EdgeInsets padding;
  static const maxHeight = 400.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final below = constraints.maxHeight - padding.bottom - anchor.bottom - 8;
    final above = anchor.top - padding.top - 8;
    final room = below >= 240 || below >= above ? below : above;
    return BoxConstraints(
      minWidth: anchor.width,
      maxWidth: anchor.width,
      maxHeight: room.clamp(120.0, maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = size.height - padding.bottom - anchor.bottom - 8;
    final fitsBelow = childSize.height <= below || below >= anchor.top - padding.top - 8;
    final y = fitsBelow ? anchor.bottom + 2 : anchor.top - childSize.height - 2;
    return Offset(anchor.left, y.clamp(padding.top, size.height - childSize.height));
  }

  @override
  bool shouldRelayout(_Below old) => old.anchor != anchor || old.padding != padding;
}

/// The search box, then "All" and each choice that matches it.
class _ChoiceList extends StatefulWidget {
  const _ChoiceList({required this.label, required this.value, required this.options});
  final String label;
  final String? value;
  final Map<String, int> options;

  @override
  State<_ChoiceList> createState() => _ChoiceListState();
}

class _ChoiceListState extends State<_ChoiceList> {
  String _query = '';

  // On a PC the cursor goes straight into the search box; on a phone it waits for a tap so the
  // keyboard doesn't cover the list.
  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final matches = [
      for (final e in widget.options.entries)
        if (choiceMatches(e.key, _query)) e
    ];
    // "All" is offered while the search is empty, so it's always one tap away.
    final showAll = _query.trim().isEmpty;
    Widget row(String? v, String text) {
      final current = v == widget.value;
      return ListTile(
        key: ValueKey('choice:${v ?? '(all)'}'),
        dense: true,
        selected: current,
        selectedColor: accent,
        title: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: current ? Icon(Icons.check, size: 18, color: accent) : null,
        onTap: () => Navigator.pop(context, _Pick(v)),
      );
    }

    return Material(
      color: AppColors.surface,
      elevation: 8,
      borderRadius: AppShape.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            key: ValueKey('choice-search-${widget.label}'),
            autofocus: _desktop,
            decoration: InputDecoration(
              hintText: 'Search ${widget.label.toLowerCase()}',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
            // Enter picks the first match.
            onSubmitted: (text) {
              if (text.trim().isEmpty) return;
              for (final k in widget.options.keys) {
                if (choiceMatches(k, text)) {
                  Navigator.pop(context, _Pick(k));
                  return;
                }
              }
            },
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              if (showAll) row(null, 'All'),
              for (final e in matches) row(e.key, '${e.key}  (${e.value})'),
              if (matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nothing matches', style: TextStyle(color: AppColors.textDim)),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
