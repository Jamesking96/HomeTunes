// Film collections on the TV (step 4; plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): a
// collection's tile on the Videos screen, its page (its films as tiles, Play / Continue the next
// one), and everything in the options panel with the remote: Add to a collection / Remove from
// it on a film, and on a collection Rename, Description, Order, Change picture and Delete.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_group.dart';
import '../../models/video_item.dart';
import '../../state/settings/settings_groups.dart' as prefs;
import '../../state/video_groups.dart' show isFilm;
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../screens/video_group_screen.dart' show GroupPicture, groupDetails;
import '../theme.dart';
import 'tv_browse.dart';
import 'tv_detail.dart';
import 'tv_items.dart';
import 'tv_keyboard.dart' show showTvTextInput;
import 'tv_options.dart';
import 'tv_pictures.dart' show showTvPictureSearch;
import 'tv_widgets.dart';

/// A collection of films as a tile (the Videos screen's Collections tab).
TvTile tvGroupTile(BuildContext context, VideoGroup g, {FocusNode? node, double width = 180, double aspectRatio = 16 / 9}) {
  final videos = context.read<VideoLibraryModel>();
  final films = videos.filmsIn(g);
  return TvTile(
    key: ValueKey('tv-group:${g.id}'),
    focusNode: node,
    width: width,
    aspectRatio: aspectRatio,
    picture: Stack(fit: StackFit.expand, children: [
      GroupPicture(films: films, group: g),
      Positioned(
        right: 6,
        top: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.collections_bookmark_outlined, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text('${films.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ),
    ]),
    title: g.name,
    subtitle: 'Collection · ${groupDetails(films)}',
    onPressed: () => context.read<AppNav>().openVideoGroup(g.id),
    onHold: () => showTvGroupOptions(context, g),
  );
}

/// A collection's page on the TV: its picture and details, Play / Continue, then its films.
class TvGroupPage extends StatelessWidget {
  const TvGroupPage({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final videos = context.watch<VideoLibraryModel>();
    final nav = context.read<AppNav>();
    final g = videos.groups.byId(groupId);
    if (g == null) return const TvMissingPage(icon: Icons.video_library_outlined, title: 'This collection has been deleted');
    final films = videos.filmsIn(g);
    final next = videos.nextInGroup(g);
    final nextVideo = next == null ? null : videos.nextUp(next);
    final started = nextVideo != null && (videos.placeOf(nextVideo.id)?.inProgress ?? false);
    final watched = videos.watchedInGroup(g);
    return TvPageHintsHere(
      hints: tvPageHints,
      child: Material(
        color: AppColors.bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin, TvStyle.topMargin, 20, TvStyle.bottomMargin),
          child: TvAzGrid<VideoCollection>(
            items: films,
            tileWidth: 180,
            aspectRatio: 16 / 9,
            header: TvDetailHeader(
              picture: GroupPicture(films: films, group: g),
              pictureWidth: 300,
              aspectRatio: 16 / 9,
              kind: 'COLLECTION',
              title: g.name,
              lines: [
                [
                  groupDetails(films),
                  if (films.isNotEmpty) watched == films.length ? 'all watched' : '$watched watched',
                ].join(' · '),
                ?g.description,
              ],
              buttons: [
                if (next != null && nextVideo != null)
                  TvButton(
                    key: const ValueKey('tv-group-play'),
                    label: '${started ? 'Continue' : 'Play'}: ${next.name}',
                    icon: Icons.play_arrow,
                    primary: true,
                    onPressed: () => nav.openVideo(nextVideo),
                  ),
                TvIconButton(
                  icon: Icons.more_horiz,
                  label: 'More options',
                  onPressed: () => showTvGroupOptions(context, g, onPage: true),
                ),
              ],
            ),
            itemBuilder: (context, c, i, node, w) => tvCollectionTile(context, c, node: node, width: w, aspectRatio: 16 / 9),
          ),
        ),
      ),
    );
  }
}

/// A collection's options panel.
Future<void> showTvGroupOptions(BuildContext context, VideoGroup g, {bool onPage = false}) {
  final videos = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final films = videos.filmsIn(g);
  final next = videos.nextInGroup(g);
  final nextVideo = next == null ? null : videos.nextUp(next);
  return showTvOptions(context, title: g.name, subtitle: 'Collection · ${groupDetails(films)}', options: [
    if (!onPage) ...[
      if (next != null && nextVideo != null) TvOption('Play ${next.name}', Icons.play_arrow, () => nav.openVideo(nextVideo)),
      TvOption('Open the collection', Icons.collections_bookmark_outlined, () => nav.openVideoGroup(g.id)),
    ],
    TvOption('Rename', Icons.drive_file_rename_outline, opensMore: true, () async {
      final to = await showTvTextInput(context, title: 'Rename the collection', initial: g.name);
      if (to != null && to.trim().isNotEmpty) videos.groups.rename(g, to);
    }),
    TvOption(g.description == null ? 'Add a description' : 'Change the description', Icons.notes, opensMore: true, () async {
      final to = await showTvTextInput(context, title: 'Description', initial: g.description ?? '', multiline: true);
      if (to != null) videos.groups.describe(g, to);
    }),
    TvOption('Order: ${g.order.label}', Icons.sort, opensMore: true, () {
      showTvOptions(context, title: 'Films in order', options: [
        for (final o in [VideoGroupOrder.year, VideoGroupOrder.name])
          TvOption(o.label, g.order == o ? Icons.check : Icons.sort, () => videos.groups.setOrder(g, o)),
        if (g.order == VideoGroupOrder.own)
          TvOption(VideoGroupOrder.own.label, Icons.check, subtitle: 'Set on the computer or phone', () {}),
      ]);
    }),
    TvOption('Change picture', Icons.image_outlined, opensMore: true, () async {
      final online = context.read<prefs.OnlineSettings>().onlineVideoArt;
      await showTvOptions(context, title: 'Picture for "${g.name}"', options: [
        if (online)
          TvOption('Search online', Icons.travel_explore, opensMore: true, () async {
            final bytes = await showTvPictureSearch(context, query: g.name, hint: 'film', forPoster: true);
            if (bytes != null) await videos.setGroupPoster(g, bytes);
          }),
        if (g.poster != null)
          TvOption('Use its films\' posters', Icons.grid_view, () => videos.setGroupPoster(g, null)),
      ]);
    }),
    TvOption('Delete the collection', Icons.delete_outline, opensMore: true, () {
      tvConfirm(context, title: 'Delete "${g.name}"?', subtitle: 'The films stay where they are', yes: 'Delete it', run: () {
        if (onPage) Navigator.of(context).maybePop();
        videos.groups.delete(g);
        videos.setGroupPoster(g, null);
      });
    }),
  ]);
}

/// On a film's options panel: Add to a collection ›, and Remove from each collection it's in.
List<TvOption> tvGroupOptionsFor(BuildContext context, VideoCollection c) {
  final videos = context.read<VideoLibraryModel>();
  if (!isFilm(c)) return const [];
  return [
    TvOption('Add to a collection', Icons.library_add_outlined, opensMore: true, () {
      showTvOptions(context, title: 'Add to a collection', subtitle: c.name, options: [
        for (final g in videos.groups.all)
          TvOption(g.name, g.keys.contains(c.key) ? Icons.check_circle : Icons.collections_bookmark_outlined,
              subtitle: g.keys.length == 1 ? '1 film' : '${g.keys.length} films', () {
            final n = videos.groups.add(g, [c]);
            tvNotice(context, n == 0 ? 'Already in ${g.name}' : 'Added to ${g.name}');
          }),
        TvOption('New collection', Icons.add, opensMore: true, () async {
          final name = await showTvTextInput(context, title: 'Name the new collection', hint: 'James Bond, Pokémon…');
          if (name == null || name.trim().isEmpty || !context.mounted) return;
          final g = videos.groups.create(name, [c]);
          tvNotice(context, 'Made ${g.name}');
        }),
      ]);
    }),
    for (final g in videos.groups.of(c.key))
      TvOption('Remove from ${g.name}', Icons.playlist_remove, () => videos.groups.remove(g, [c.key])),
  ];
}

/// Suggested collections on the TV (step 5, 9 Nov 2026): each suggestion's panel offers to make
/// it (as it is, or named first) or "No thanks". Nothing is made without a yes.
Future<void> showTvGroupSuggestions(BuildContext context) async {
  final videos = context.read<VideoLibraryModel>();
  tvNotice(context, 'Looking for collections to suggest…');
  final list = await videos.groupSuggestions();
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  if (list.isEmpty) {
    await showTvOptions(context, title: 'Suggested collections', subtitle: 'Nothing to suggest right now', options: [
      TvOption('OK', Icons.check, () {}),
      if (videos.hasDismissedSuggestions)
        TvOption('Show ones I said no to', Icons.undo, () => videos.undismissSuggestions()),
    ]);
    return;
  }
  String films(int n) => n == 1 ? '1 film' : '$n films';
  await showTvOptions(context, title: 'Suggested collections', subtitle: 'Nothing is made until you choose', options: [
    // Every suggestion at once (9 Nov 2026).
    if (list.length > 1)
      TvOption('Use all ${list.length}', Icons.done_all, subtitle: list.map((s) => s.into?.name ?? s.name).join(' · '), () {
        for (final s in list) {
          videos.acceptSuggestion(s, s.films);
        }
        tvNotice(context, 'Made ${list.length} collections');
      }),
    for (final s in list)
      TvOption(s.into == null ? s.name : 'Add to ${s.into!.name}', Icons.auto_awesome_outlined,
          subtitle: '${films(s.films.length)} · ${s.why}', opensMore: true, () {
        showTvOptions(context, title: s.into == null ? s.name : 'Add to ${s.into!.name}', subtitle: s.films.map((c) => c.name).join(' · '), options: [
          TvOption(s.into == null ? 'Make the collection' : 'Add ${films(s.films.length)}', Icons.check, () {
            final g = videos.acceptSuggestion(s, s.films);
            tvNotice(context, s.into == null ? 'Made ${g.name}' : 'Added to ${g.name}');
          }),
          if (s.into == null)
            TvOption('Name it, then make it', Icons.drive_file_rename_outline, opensMore: true, () async {
              final name = await showTvTextInput(context, title: 'Name the collection', initial: s.name);
              if (name == null || name.trim().isEmpty || !context.mounted) return;
              final g = videos.acceptSuggestion(s, s.films, name: name);
              tvNotice(context, 'Made ${g.name}');
            }),
          TvOption('No thanks', Icons.close, () => videos.dismissSuggestion(s)),
        ]);
      }),
  ]);
}
