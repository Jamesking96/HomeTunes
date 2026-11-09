// Film collections, step 3 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): making and
// changing the user's groups of films on the PC and phone. "Add to collection…" on a film (its
// menu, or several picked in Select mode), "Remove from <collection>", and on a collection:
// Edit collection (name, description, order: by year, by name or your own, dragged), Change
// picture (a file or online; or the films' posters, tiled) and Delete (the films stay).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_group.dart';
import '../../models/video_item.dart';
import '../../state/settings/settings_groups.dart' as prefs;
import '../../state/video_groups.dart' show isFilm;
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../widgets/picture_choice.dart';
import '../widgets/track_tile.dart' show askForName;
import 'video_pictures.dart' show preparePicture, showPictureSearch;

/// "Add to collection…" for [picked] (shows are left out: they stay their own collections).
/// Lists the collections, ticked where all the films are already in; or a new one.
Future<void> showAddToGroup(BuildContext context, List<VideoCollection> picked) async {
  final model = context.read<VideoLibraryModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final films = [for (final c in picked) if (isFilm(c)) c];
  if (films.isEmpty) {
    messenger?.showSnackBar(const SnackBar(content: Text('Only films go into collections; shows stay as they are.')));
    return;
  }
  final what = films.length == 1 ? '"${films.single.name}"' : '${films.length} films';
  final chosen = await showDialog<Object>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Add $what to a collection'),
      children: [
        SimpleDialogOption(
          key: const ValueKey('group-new'),
          onPressed: () => Navigator.pop(ctx, 'new'),
          child: const ListTile(leading: Icon(Icons.add), title: Text('New collection…')),
        ),
        for (final g in model.groups.all)
          SimpleDialogOption(
            key: ValueKey('group-pick:${g.id}'),
            onPressed: () => Navigator.pop(ctx, g),
            child: ListTile(
              leading: Icon(films.every((f) => g.keys.contains(f.key)) ? Icons.check_circle : Icons.collections_bookmark_outlined),
              title: Text(g.name),
              subtitle: Text(g.keys.length == 1 ? '1 film' : '${g.keys.length} films'),
            ),
          ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;
  if (chosen == 'new') {
    final name = await askForName(context, title: 'New collection');
    if (name == null || name.trim().isEmpty) return;
    final g = model.groups.create(name, films);
    messenger?.showSnackBar(SnackBar(content: Text('Made "${g.name}" with $what')));
    return;
  }
  final g = chosen as VideoGroup;
  final n = model.groups.add(g, films);
  messenger?.showSnackBar(SnackBar(content: Text(n == 0 ? 'Already in "${g.name}"' : 'Added to "${g.name}"')));
}

/// The menu items for one film: Add to collection…, and Remove from each collection it's in.
/// Values: `group-add` and `group-remove:<id>` (see [runGroupMenuChoice]).
List<PopupMenuEntry<String>> groupMenuItems(VideoLibraryModel model, VideoCollection c) => [
      if (isFilm(c))
        const PopupMenuItem(
          key: ValueKey('menu-group-add'),
          value: 'group-add',
          child: ListTile(leading: Icon(Icons.library_add_outlined), title: Text('Add to collection…')),
        ),
      for (final g in model.groups.of(c.key))
        PopupMenuItem(
          key: ValueKey('menu-group-remove:${g.id}'),
          value: 'group-remove:${g.id}',
          child: ListTile(leading: const Icon(Icons.playlist_remove), title: Text('Remove from "${g.name}"')),
        ),
    ];

/// Runs a choice from [groupMenuItems]. Returns whether it was one of them.
Future<bool> runGroupMenuChoice(BuildContext context, String? choice, VideoCollection c) async {
  if (choice == 'group-add') {
    await showAddToGroup(context, [c]);
    return true;
  }
  if (choice != null && choice.startsWith('group-remove:')) {
    final model = context.read<VideoLibraryModel>();
    final g = model.groups.byId(choice.substring('group-remove:'.length));
    if (g != null) model.groups.remove(g, [c.key]);
    return true;
  }
  return false;
}

/// Edit collection: its name, description and order (your own order: drag the films).
Future<void> showEditGroup(BuildContext context, VideoGroup g) async {
  final model = context.read<VideoLibraryModel>();
  await showDialog<void>(context: context, builder: (_) => _EditGroupDialog(model: model, group: g));
}

class _EditGroupDialog extends StatefulWidget {
  const _EditGroupDialog({required this.model, required this.group});
  final VideoLibraryModel model;
  final VideoGroup group;

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final _name = TextEditingController(text: widget.group.name);
  late final _about = TextEditingController(text: widget.group.description ?? '');
  late VideoGroupOrder _order = widget.group.order;
  // The films in the order they're shown now (for dragging into your own order).
  late List<VideoCollection> _films = widget.model.filmsIn(widget.group);

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    super.dispose();
  }

  void _save() {
    final groups = widget.model.groups;
    final g = widget.group;
    if (_name.text.trim().isNotEmpty) groups.rename(g, _name.text);
    groups.describe(g, _about.text);
    if (_order == VideoGroupOrder.own) {
      groups.reorder(g, [for (final f in _films) f.key]);
    } else {
      groups.setOrder(g, _order);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit collection'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const ValueKey('group-name'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            key: const ValueKey('group-description'),
            controller: _about,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 16),
          const Text('Films in order'),
          const SizedBox(height: 4),
          SegmentedButton<VideoGroupOrder>(
            segments: [
              for (final o in VideoGroupOrder.values)
                ButtonSegment(value: o, label: Text(o.label), icon: Icon(switch (o) {
                  VideoGroupOrder.year => Icons.calendar_today_outlined,
                  VideoGroupOrder.name => Icons.sort_by_alpha,
                  VideoGroupOrder.own => Icons.drag_indicator,
                })),
            ],
            selected: {_order},
            onSelectionChanged: (s) => setState(() {
              _order = s.single;
              if (_order != VideoGroupOrder.own) {
                // Show the order it would be in.
                final copy = VideoGroup(id: 'x', name: 'x', keys: [...widget.group.keys], order: _order);
                _films = widget.model.groups.films(copy, widget.model.collectionNamed);
              }
            }),
          ),
          const SizedBox(height: 8),
          if (_order == VideoGroupOrder.own)
            Text('Drag to put them in your own order.', style: Theme.of(context).textTheme.bodySmall),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: _order == VideoGroupOrder.own,
              onReorderItem: (from, to) => setState(() => _films.insert(to, _films.removeAt(from))),
              children: [
                for (final f in _films)
                  ListTile(
                    key: ValueKey('group-film:${f.key}'),
                    dense: true,
                    title: Text(f.name),
                    subtitle: f.year == null ? null : Text('${f.year}'),
                  ),
              ],
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Delete collection (asks first). The films stay as they are.
Future<bool> confirmDeleteGroup(BuildContext context, VideoGroup g) async {
  final model = context.read<VideoLibraryModel>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${g.name}"?'),
      content: const Text('Only the collection goes. Its films stay where they are, with your places in them.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true) return false;
  model.groups.delete(g);
  await model.setGroupPoster(g, null); // its own picture, if any, is tidied away
  return true;
}

/// Change picture… for a collection: a file, or one found online; or back to its films' posters.
Future<void> showGroupPosterOptions(BuildContext context, VideoGroup g) async {
  final model = context.read<VideoLibraryModel>();
  final online = context.read<prefs.OnlineSettings>().onlineVideoArt;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final how = await showPictureChoices(context, title: 'Picture for "${g.name}"', keyPrefix: 'group-picture', choices: [
    const PictureChoice('file', Icons.image_outlined, 'Choose an image file…', 'A picture you already have'),
    PictureChoice('online', Icons.travel_explore, 'Search online…',
        online ? 'Posters from TVmaze, AniList and Wikipedia' : 'Switched off in Settings › Online lookups',
        enabled: online),
    if (g.poster != null) const PictureChoice('auto', Icons.grid_view, 'Use its films\' posters', 'Up to four of them, side by side'),
  ]);
  if (how == null || !context.mounted) return;
  try {
    List<int>? bytes;
    switch (how) {
      case 'auto':
        await model.setGroupPoster(g, null);
        return;
      case 'file':
        final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture');
        final path = file?.path;
        if (path == null) return;
        bytes = await preparePicture(await File(path).readAsBytes());
      case 'online':
        bytes = await showPictureSearch(context, query: g.name, hint: 'film', forPoster: true);
    }
    if (bytes == null) return;
    await model.setGroupPoster(g, bytes);
    messenger?.showSnackBar(SnackBar(content: Text('New picture for "${g.name}"')));
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: $e')));
  }
}

/// A collection's menu (right-click / press and hold on its card, ⋮ on its page).
Future<void> showGroupMenu(BuildContext context, VideoGroup g, {required Offset at, bool onPage = false}) async {
  final model = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final next = model.nextInGroup(g);
  final nextVideo = next == null ? null : model.nextUp(next);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (!onPage)
        const PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open collection'))),
      if (next != null && nextVideo != null)
        PopupMenuItem(
          value: 'play',
          child: ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(model.placeOf(nextVideo.id)?.inProgress ?? false ? 'Continue' : 'Play'),
            subtitle: Text(next.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      const PopupMenuItem(
          key: ValueKey('menu-group-edit'),
          value: 'edit',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit collection…'))),
      const PopupMenuItem(
          value: 'picture', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Change picture…'))),
      const PopupMenuItem(
          key: ValueKey('menu-group-delete'),
          value: 'delete',
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete collection'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'open':
      nav.openVideoGroup(g.id);
    case 'play':
      if (nextVideo != null) nav.openVideo(nextVideo);
    case 'edit':
      await showEditGroup(context, g);
    case 'picture':
      await showGroupPosterOptions(context, g);
    case 'delete':
      final gone = await confirmDeleteGroup(context, g);
      if (gone && onPage && context.mounted) Navigator.of(context).maybePop();
  }
}
