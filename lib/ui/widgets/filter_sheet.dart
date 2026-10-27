// The filter bar and filter sheet shared by the Artists, Albums and Songs tabs in Your Library
// (0.1.18), the Audiobooks tab and the Videos tab. The bar has a "filter by title" box, a filter
// button and a sort menu; the sheet offers one dropdown per FilterField (artist, album, genre,
// decade…; state/filters.dart). Refactor phase 12: was music_filter_sheet.dart, MusicFilterBar
// and showMusicFilterSheet.
import 'package:flutter/material.dart';

import '../../state/filters.dart';
import '../../state/sort_order.dart';
import '../theme.dart';
import 'search_choice_field.dart';
import '../tv/tv_keyboard.dart' show TvTextField;

export '../../state/sort_order.dart';

/// Title box + filter button + sort menu, shown at the top of a library tab.
class FilterBar<S> extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool filtersActive;
  final VoidCallback onFilter;
  final S sort;
  final List<S> sorts;
  final String Function(S) sortLabel;
  final ValueChanged<S> onSort;

  /// Ascending / descending (0.1.69, see [SortMenu]).
  final SortWords Function(S)? sortWords;
  final bool reversed;
  final ValueChanged<bool>? onReversed;

  /// Extra buttons before Filter (the Artists tab's list / grid button, 0.1.52).
  final List<Widget> actions;

  const FilterBar({
    super.key,
    this.actions = const [],
    this.sortWords,
    this.reversed = false,
    this.onReversed,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.filtersActive,
    required this.onFilter,
    required this.sort,
    required this.sorts,
    required this.sortLabel,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(children: [
        Expanded(
          child: TvTextField(field: TextField(
            key: const ValueKey('library-title-filter'),
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              // The clear button only shows once something is typed.
              suffixIcon: ValueListenableBuilder(
                valueListenable: controller,
                builder: (_, v, _) => v.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
              border: OutlineInputBorder(borderRadius: AppShape.circular(24), borderSide: BorderSide.none),
              filled: true,
            ),
          )),
        ),
        ...actions,
        IconButton(
          tooltip: 'Filter',
          icon: Badge(isLabelVisible: filtersActive, smallSize: 8, child: const Icon(Icons.filter_list)),
          onPressed: onFilter,
        ),
        SortMenu<S>(
          sort: sort,
          sorts: sorts,
          sortLabel: sortLabel,
          onSort: onSort,
          sortWords: sortWords,
          reversed: reversed,
          onReversed: onReversed,
        ),
      ]),
    );
  }
}

enum _Direction { ascending, descending }

/// The sort button's menu: the sorts, then (0.1.69) Ascending and Descending with what they
/// mean for the chosen sort ("A to Z", "Newest first"…). Shared by the Library tabs, Audiobooks
/// and Videos.
class SortMenu<S> extends StatelessWidget {
  final S sort;
  final List<S> sorts;
  final String Function(S) sortLabel;
  final ValueChanged<S> onSort;

  /// What [sort] orders by; null leaves out Ascending / Descending.
  final SortWords Function(S)? sortWords;

  /// Whether the list is the other way round from the sort's usual direction.
  final bool reversed;
  final ValueChanged<bool>? onReversed;

  const SortMenu({
    super.key,
    required this.sort,
    required this.sorts,
    required this.sortLabel,
    required this.onSort,
    this.sortWords,
    this.reversed = false,
    this.onReversed,
  });

  @override
  Widget build(BuildContext context) {
    final words = sortWords?.call(sort);
    final descending = words != null && words.startsDescending != reversed;
    return PopupMenuButton<Object>(
      key: const ValueKey('sort-menu'),
      tooltip: 'Sort',
      icon: Icon(reversed ? Icons.swap_vert : Icons.sort),
      onSelected: (v) {
        if (v is _Direction) {
          if (words != null) onReversed?.call((v == _Direction.descending) != words.startsDescending);
        } else {
          onSort(v as S);
        }
      },
      itemBuilder: (_) => [
        for (final s in sorts)
          CheckedPopupMenuItem<Object>(value: s as Object, checked: s == sort, child: Text(sortLabel(s))),
        if (words != null && onReversed != null) ...[
          const PopupMenuDivider(),
          CheckedPopupMenuItem<Object>(
            key: const ValueKey('sort-ascending'),
            value: _Direction.ascending,
            checked: !descending,
            child: Text('Ascending (${words.words.$1})'),
          ),
          CheckedPopupMenuItem<Object>(
            key: const ValueKey('sort-descending'),
            value: _Direction.descending,
            checked: descending,
            child: Text('Descending (${words.words.$2})'),
          ),
        ],
      ],
    );
  }
}

/// Opens the filter sheet for [items]. Returns the new filters, or null if dismissed.
Future<Filters?> showFilterSheet<T>(
  BuildContext context, {
  required List<T> items,
  required List<FilterField<T>> fields,
  required Filters current,
  required String showLabel,
}) =>
    showModalBottomSheet<Filters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _FilterSheet<T>(items: items, fields: fields, current: current, showLabel: showLabel),
    );

class _FilterSheet<T> extends StatefulWidget {
  final List<T> items;
  final List<FilterField<T>> fields;
  final Filters current;
  final String showLabel;
  const _FilterSheet({required this.items, required this.fields, required this.current, required this.showLabel});

  @override
  State<_FilterSheet<T>> createState() => _FilterSheetState<T>();
}

class _FilterSheetState<T> extends State<_FilterSheet<T>> {
  /// The filters being chosen; only handed back when the Show button is pressed.
  late Filters _f = widget.current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Show only', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final field in widget.fields) _dropdown(field),
          const SizedBox(height: 4),
          Row(children: [
            TextButton(onPressed: () => Navigator.pop(context, Filters.none), child: const Text('Clear all')),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, _f), child: Text(widget.showLabel)),
          ]),
        ]),
      ),
    );
  }

  /// One drop-down: "All" plus each choice (narrowed by the other picks) and its count, with a
  /// search box at the top of the list (0.1.49, `SearchChoiceField`).
  Widget _dropdown(FilterField<T> field) {
    final value = _f.picked[field.label];
    final options = {..._f.choices(widget.items, widget.fields, field)};
    // The Source field (0.2.2) only when there's a choice to make.
    // (Judged over everything on the tab, so other picks don't make it come and go.)
    if (field.onlyWhenSeveral &&
        value == null &&
        Filters.none.choices(widget.items, widget.fields, field).length < 2) {
      return const SizedBox.shrink();
    }
    // Keep the current pick even if the other picks narrowed it away.
    if (value != null && !options.containsKey(value)) options[value] = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SearchChoiceField(
        key: ValueKey('filter-${field.label}'),
        label: field.label,
        value: value,
        options: options,
        onChanged: (v) => setState(() => _f = _f.withValue(field.label, v)),
      ),
    );
  }
}
