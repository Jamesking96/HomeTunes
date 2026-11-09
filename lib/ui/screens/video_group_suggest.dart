// Film collections, step 5 (9 Nov 2026): "Suggested collections" on the PC and phone. Lists
// what HomeTunes could put together (the server's own collections, the films' .nfo sets,
// similar names), each with its films ticked; nothing is made until "Make collection".
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_group_suggestions.dart';
import '../../state/video_library_model.dart';

/// Opens the suggestions. Returns how many collections were made or added to.
Future<int> showGroupSuggestions(BuildContext context) async {
  final model = context.read<VideoLibraryModel>();
  final made = await showDialog<int>(
    context: context,
    builder: (_) => ChangeNotifierProvider.value(value: model, child: const _SuggestionsDialog()),
  );
  return made ?? 0;
}

class _SuggestionsDialog extends StatefulWidget {
  const _SuggestionsDialog();

  @override
  State<_SuggestionsDialog> createState() => _SuggestionsDialogState();
}

class _SuggestionsDialogState extends State<_SuggestionsDialog> {
  List<GroupSuggestion>? _list;
  final Map<GroupSuggestion, Set<String>> _ticked = {};
  final Map<GroupSuggestion, TextEditingController> _names = {};
  int _made = 0;

  @override
  void initState() {
    super.initState();
    final model = context.read<VideoLibraryModel>();
    // What's known here shows at once; the server's own collections join when they arrive.
    _show(model.localSuggestions);
    model.groupSuggestions().then((all) {
      if (mounted) _show(all);
    });
  }

  void _show(List<GroupSuggestion> list) => setState(() {
        _list = list;
        _ticked.clear();
        for (final s in list) {
          _ticked[s] = {for (final c in s.films) c.key};
          _names.putIfAbsent(s, () => TextEditingController(text: s.name));
        }
      });

  @override
  void dispose() {
    for (final c in _names.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _drop(GroupSuggestion s) => setState(() => _list = [...?_list]..remove(s));

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final list = _list;
    return AlertDialog(
      title: const Text('Suggested collections'),
      content: SizedBox(
        width: 520,
        child: list == null
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : list.isEmpty
                ? Text(
                    key: const ValueKey('suggest-none'),
                    _made > 0
                        ? 'That\'s every suggestion.'
                        : 'Nothing to suggest right now. Films with similar names, an .nfo series '
                            '(<set>) or one of the server\'s own collections show up here.',
                  )
                : ListView(shrinkWrap: true, children: [for (final s in list) _card(context, model, s)]),
      ),
      actions: [
        if (model.hasDismissedSuggestions)
          TextButton(
            onPressed: () async {
              await model.undismissSuggestions();
              if (mounted) _show(await model.groupSuggestions());
            },
            child: const Text('Show ones I said no to'),
          ),
        TextButton(key: const ValueKey('suggest-close'), onPressed: () => Navigator.pop(context, _made), child: const Text('Close')),
      ],
    );
  }

  Widget _card(BuildContext context, VideoLibraryModel model, GroupSuggestion s) {
    final ticked = _ticked[s]!;
    final into = s.into;
    return Card(
      key: ValueKey('suggest:${s.dismissKey}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (into == null)
            TextField(
              key: ValueKey('suggest-name:${s.dismissKey}'),
              controller: _names[s],
              decoration: const InputDecoration(labelText: 'Name', isDense: true),
            )
          else
            Text('Add to "${into.name}"', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(s.why, style: Theme.of(context).textTheme.bodySmall),
          for (final c in s.films)
            CheckboxListTile(
              key: ValueKey('suggest-film:${c.key}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: ticked.contains(c.key),
              title: Text(c.year == null ? c.name : '${c.name} (${c.year})'),
              onChanged: (on) => setState(() => on == true ? ticked.add(c.key) : ticked.remove(c.key)),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              key: ValueKey('suggest-no:${s.dismissKey}'),
              onPressed: () async {
                _drop(s);
                await model.dismissSuggestion(s);
              },
              child: const Text('No thanks'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('suggest-yes:${s.dismissKey}'),
              onPressed: ticked.isEmpty ? null : () => _accept(model, s),
              child: Text(into == null ? 'Make collection' : 'Add ${ticked.length == 1 ? 'film' : 'films'}'),
            ),
          ]),
        ]),
      ),
    );
  }

  void _accept(VideoLibraryModel model, GroupSuggestion s) {
    final films = <VideoCollection>[for (final c in s.films) if (_ticked[s]!.contains(c.key)) c];
    final g = model.acceptSuggestion(s, films, name: _names[s]?.text);
    _made++;
    _drop(s);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(s.into == null ? 'Made "${g.name}" with ${films.length} films' : 'Added ${films.length} to "${g.name}"')));
  }
}
