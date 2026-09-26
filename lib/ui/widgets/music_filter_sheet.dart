// The filter bar and filter sheet shared by the Artists, Albums and Songs tabs in Your Library
// (0.1.18). The bar has a "filter by title" box, a filter button and a sort menu; the sheet
// offers one dropdown per FilterField (artist, album, genre, decade…), like the Books tab's.
import 'package:flutter/material.dart';

import '../../state/music_filters.dart';
import '../theme.dart';

/// Title box + filter button + sort menu, shown at the top of a library tab.
class MusicFilterBar<S> extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool filtersActive;
  final VoidCallback onFilter;
  final S sort;
  final List<S> sorts;
  final String Function(S) sortLabel;
  final ValueChanged<S> onSort;

  const MusicFilterBar({
    super.key,
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
          child: TextField(
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              filled: true,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Filter',
          icon: Badge(isLabelVisible: filtersActive, smallSize: 8, child: const Icon(Icons.filter_list)),
          onPressed: onFilter,
        ),
        PopupMenuButton<S>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final s in sorts) CheckedPopupMenuItem(value: s, checked: s == sort, child: Text(sortLabel(s))),
          ],
        ),
      ]),
    );
  }
}

/// Opens the filter sheet for [items]. Returns the new filters, or null if dismissed.
Future<MusicFilters?> showMusicFilterSheet<T>(
  BuildContext context, {
  required List<T> items,
  required List<FilterField<T>> fields,
  required MusicFilters current,
  required String showLabel,
}) =>
    showModalBottomSheet<MusicFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _MusicFilterSheet<T>(items: items, fields: fields, current: current, showLabel: showLabel),
    );

class _MusicFilterSheet<T> extends StatefulWidget {
  final List<T> items;
  final List<FilterField<T>> fields;
  final MusicFilters current;
  final String showLabel;
  const _MusicFilterSheet({required this.items, required this.fields, required this.current, required this.showLabel});

  @override
  State<_MusicFilterSheet<T>> createState() => _MusicFilterSheetState<T>();
}

class _MusicFilterSheetState<T> extends State<_MusicFilterSheet<T>> {
  /// The filters being chosen; only handed back when the Show button is pressed.
  late MusicFilters _f = widget.current;

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
            TextButton(onPressed: () => Navigator.pop(context, MusicFilters.none), child: const Text('Clear all')),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, _f), child: Text(widget.showLabel)),
          ]),
        ]),
      ),
    );
  }

  /// One dropdown: "All" plus each choice (narrowed by the other picks) and its count.
  Widget _dropdown(FilterField<T> field) {
    final value = _f.picked[field.label];
    final options = {..._f.choices(widget.items, widget.fields, field)};
    // Keep the current pick even if the other picks narrowed it away.
    if (value != null && !options.containsKey(value)) options[value] = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        key: ValueKey('filter-${field.label}'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final e in options.entries)
            DropdownMenuItem<String?>(value: e.key, child: Text('${e.key}  (${e.value})', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => setState(() => _f = _f.withValue(field.label, v)),
      ),
    );
  }
}
