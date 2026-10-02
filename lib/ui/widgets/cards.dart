// Small building blocks for the browse screens (Home, Library, Search, artist pages):
// album and artist tiles, the horizontal "Shelf" carousel, the grid column helper and the
// friendly "nothing here yet" message. Tapping a tile opens its page through AppNav.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/range_select.dart';
import '../../state/selection_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../../state/library_model.dart';
import 'artwork.dart';
import 'quick_actions.dart';

/// Album tile for grids and carousels. Hovering over the cover with a mouse shows a round
/// play button that plays the album straight away (0.1.26).
class AlbumCard extends StatelessWidget {
  final Album album;
  /// Fixed width for shelves; null lets a grid decide.
  final double? width;
  /// Second line shows the artist; if false, the year instead (used on an artist's own page).
  final bool showArtist;
  /// The keys of all the albums shown alongside this one, for "Select all".
  final List<String> scope;
  /// What a tap does instead of opening the album page (the artist page shows the songs in
  /// place). When set, the right-click / press-and-hold menu gets "Open album page".
  final VoidCallback? onTap;
  /// Outlined in the highlight colour (the album whose songs are showing).
  final bool highlighted;
  const AlbumCard({
    super.key,
    required this.album,
    this.width,
    this.showArtist = true,
    this.scope = const [],
    this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final favourite = context.select<PlaylistsModel, bool>((p) => p.isFavouriteAlbum(album));
    void openPage() => context.read<AppNav>().openAlbum(album);
    final card = SelectableCard(
      id: album.key,
      kind: SelectKind.albums,
      scope: scope,
      favourite: favourite,
      highlighted: highlighted,
      actionsFor: (keys) {
        final lib = context.read<LibraryModel>();
        // Just this one: use it as shown. Several: look each one up.
        final albums = keys.length == 1 && keys.first == album.key
            ? [album]
            : [for (final k in keys) lib.albumByKey(k)].whereType<Album>().toList();
        return albumActions(context, albums);
      },
      onOpen: onTap ?? openPage,
      onOpenPage: onTap == null ? null : openPage,
      openPageLabel: 'Open album page',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: HoverPlayCover(
              key: ValueKey('hover-play:${album.key}'),
              tooltip: 'Play ${album.title}',
              onPlay: () => context
                  .read<PlayerModel>()
                  .playTracks(album.tracks, label: 'Album · ${album.title}'),
              child: ArtworkFill(track: album.artTrack),
            ),
          ),
          const SizedBox(height: 8),
          Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            showArtist ? album.artist : (album.year?.toString() ?? 'Album'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ]),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// An album or book tile that can be selected. Tapping opens it. Right-click
/// (or press and hold on a phone) offers Select and Select all, then quick
/// actions (edit, cover, favourites, details). While selecting, a tap ticks or
/// unticks it instead of opening it, and right-clicking a ticked one offers the
/// quick actions for everything ticked. Favourites show a small heart.
class SelectableCard extends StatefulWidget {
  final String id;
  final SelectKind kind;
  /// Everything shown alongside it, for "Select all".
  final List<String> scope;
  final VoidCallback onOpen;
  final Widget child;
  final bool favourite;
  /// The quick actions for these ids (this one, or everything selected).
  final List<QuickAction> Function(List<String> ids)? actionsFor;
  /// When a tap does something other than open the page, this opens it from the menu
  /// ([openPageLabel], e.g. "Open album page").
  final VoidCallback? onOpenPage;
  final String openPageLabel;
  /// Outlined in the highlight colour without being selected (e.g. its songs are showing).
  final bool highlighted;
  const SelectableCard({
    super.key,
    required this.id,
    required this.kind,
    required this.scope,
    required this.onOpen,
    required this.child,
    this.favourite = false,
    this.actionsFor,
    this.onOpenPage,
    this.openPageLabel = 'Open page',
    this.highlighted = false,
  });

  @override
  State<SelectableCard> createState() => _SelectableCardState();
}

class _SelectableCardState extends State<SelectableCard> {
  // Where the finger or mouse last went down, so the menu opens there.
  Offset? _at;

  Future<void> _menu() async {
    final sel = context.read<SelectionModel>();
    final box = context.findRenderObject() as RenderBox;
    final at = _at ?? box.localToGlobal(box.size.center(Offset.zero));
    final kindName = widget.kind == SelectKind.books ? 'books' : 'albums';
    if (sel.selecting(widget.kind)) {
      // Pressing and holding (or right-clicking) one that isn't ticked just ticks it.
      if (!sel.contains(widget.id, kind: widget.kind)) {
        sel.toggle(widget.id, kind: widget.kind);
        return;
      }
      // A ticked one: the quick actions for everything ticked.
      final ids = sel.ids.toList();
      await showQuickActions(context, at, widget.actionsFor?.call(ids) ?? const [], header: [
        PopupMenuItem(enabled: false, child: Text('${ids.length} $kindName selected')),
        if (sel.canSelectAll) PopupMenuItem(value: () async => sel.selectScope(), child: const Text('Select all')),
        PopupMenuItem(value: () async => sel.clear(), child: const Text('Stop selecting')),
      ]);
      return;
    }
    final others = widget.scope.length;
    await showQuickActions(context, at, widget.actionsFor?.call([widget.id]) ?? const [], header: [
      if (widget.onOpenPage != null)
        PopupMenuItem(
          key: const ValueKey('menu-open-page'),
          value: () async => widget.onOpenPage!(),
          child: menuRow(Icons.open_in_new, widget.openPageLabel),
        ),
      PopupMenuItem(
        value: () async => sel.start(widget.id, kind: widget.kind, scope: widget.scope),
        child: menuRow(Icons.check_box_outlined, 'Select'),
      ),
      if (others > 1)
        PopupMenuItem(
          value: () async => sel.start(widget.id, kind: widget.kind, scope: widget.scope, all: true),
          child: menuRow(Icons.select_all, 'Select all ($others)'),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final (selecting, selected) = context.select<SelectionModel, (bool, bool)>(
        (s) => (s.selecting(widget.kind), s.contains(widget.id, kind: widget.kind)));
    final accent = Theme.of(context).colorScheme.primary;
    return Stack(children: [
      Container(
        decoration: BoxDecoration(
          borderRadius: AppShape.circular(8),
          border: Border.all(color: selected || widget.highlighted ? accent : Colors.transparent, width: 2),
          color: selected || widget.highlighted ? accent.withValues(alpha: 0.12) : null,
        ),
        child: InkWell(
          borderRadius: AppShape.circular(8),
          onTapDown: (d) => _at = d.globalPosition,
          // Selecting: a tap ticks / unticks; Shift + click ticks everything from the last one
          // clicked (0.1.47), and with nothing ticked yet starts selecting.
          onTap: () {
            if (selecting || shiftHeld) {
              context.read<SelectionModel>().pick(widget.id, widget.scope, kind: widget.kind);
            } else {
              widget.onOpen();
            }
          },
          onLongPress: _menu,
          onSecondaryTapDown: (d) {
            _at = d.globalPosition;
            _menu();
          },
          child: widget.child,
        ),
      ),
      if (widget.favourite)
        Positioned(
          right: 12,
          top: 12,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: Icon(Icons.favorite, size: 14, color: accent, semanticLabel: 'Favourite'),
            ),
          ),
        ),
      if (selecting)
        Positioned(
          left: 12,
          top: 12,
          child: IgnorePointer(
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? accent : Colors.black54,
                borderRadius: AppShape.circular(5),
                border: Border.all(color: selected ? accent : Colors.white, width: 2),
              ),
              child: selected ? Icon(Icons.check, size: 16, color: AppColors.current.onAccent) : null,
            ),
          ),
        ),
    ]);
  }
}

/// A cover that shows a round play button in its corner while the mouse is over it (0.1.26).
/// Touch screens have no hover, so there it's just the cover.
class HoverPlayCover extends StatefulWidget {
  final Widget child;
  final VoidCallback onPlay;
  final String tooltip;
  const HoverPlayCover({super.key, required this.child, required this.onPlay, this.tooltip = 'Play'});

  @override
  State<HoverPlayCover> createState() => _HoverPlayCoverState();
}

class _HoverPlayCoverState extends State<HoverPlayCover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(fit: StackFit.expand, children: [
        widget.child,
        Positioned(
          right: 8,
          bottom: 8,
          // Hidden (and not clickable) until hovered; slides up a little as it appears.
          child: IgnorePointer(
            ignoring: !_hover,
            child: AnimatedSlide(
              offset: _hover ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 150),
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Tooltip(
                  message: widget.tooltip,
                  child: Material(
                    key: const ValueKey('hover-play-button'),
                    color: accent,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onPlay,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.play_arrow_rounded, size: 26, color: AppColors.current.onAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Round artist tile.
class ArtistCard extends StatelessWidget {
  final Artist artist;
  final double? width;

  /// The line under the name ("Artist" unless given; the Artists tab's grid shows the counts).
  final String? subtitle;
  const ArtistCard({super.key, required this.artist, this.width, this.subtitle});

  @override
  Widget build(BuildContext context) {
    // Artists have no picture of their own, so borrow the first album's cover (cut to a circle).
    final art = artist.albums.isEmpty ? null : artist.albums.first.artTrack;
    final card = InkWell(
      borderRadius: AppShape.circular(8),
      onTap: () => context.read<AppNav>().openArtist(artist.name),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (_, c) => Artwork(track: art, size: c.maxWidth, radius: c.maxWidth / 2, placeholder: Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(subtitle ?? 'Artist',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ]),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Section header + horizontal carousel. On a PC, where a mouse can't swipe,
/// it has ‹ › buttons that page through it and a visible scroll bar; the
/// row can also be dragged with the mouse (see `appScrollBehavior`) or
/// scrolled with Shift + mouse wheel.
class Shelf extends StatefulWidget {
  final String title;
  /// The cards, usually AlbumCard / ArtistCard / BookCard with a fixed width.
  final List<Widget> children;
  /// Height of the card row (not counting the title).
  final double height;
  const Shelf({super.key, required this.title, required this.children, this.height = 230});

  @override
  State<Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<Shelf> {
  final _scroll = ScrollController();
  bool _canBack = false; // is there anything off to the left?
  bool _canForward = false; // …or to the right?

  // Arrows and a permanent scroll bar only on computers; phones just swipe.
  static final _desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
    // The list's length isn't known until it has been laid out, so check after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  // The cards may have changed (e.g. after a rescan), so the arrows may need updating too.
  @override
  void didUpdateWidget(Shelf old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Enables the arrows only when there's more to see that way.
  void _update() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    // The 1 px of slack stops rounding errors from leaving an arrow lit at either end.
    final back = pos.pixels > pos.minScrollExtent + 1;
    final forward = pos.pixels < pos.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  /// Moves most of a screen's width, so the last card seen stays in view.
  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (pos.pixels + direction * pos.viewportDimension * 0.85).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    // On desktop, 10 px extra at the bottom makes room for the scroll bar under the cards.
    final list = ListView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(8, 0, 8, _desktop ? 10 : 0),
      children: widget.children,
    );
    // Title row (with the ‹ › buttons when there's something to page to), then the cards.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
        child: Row(children: [
          Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          if (_desktop && (_canBack || _canForward)) ...[
            IconButton(
              tooltip: 'Scroll left',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left),
              onPressed: _canBack ? () => _page(-1) : null,
            ),
            IconButton(
              tooltip: 'Scroll right',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right),
              onPressed: _canForward ? () => _page(1) : null,
            ),
          ],
        ]),
      ),
      SizedBox(
        height: widget.height + (_desktop ? 10 : 0),
        // Resizing the window changes how much is hidden: keep the arrows right.
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _update());
            return false;
          },
          child: _desktop ? Scrollbar(controller: _scroll, thumbVisibility: true, child: list) : list,
        ),
      ),
    ]);
  }
}

/// Responsive grid column count for album grids.
/// About one column per 190 px, but never fewer than 2 or more than 8.
int gridColumns(double width) => (width / 190).floor().clamp(2, 8);

/// Friendly empty message.
/// A big dim icon, a title, an optional explanation and an optional button (e.g. "Add music").
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppColors.textDim),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}
