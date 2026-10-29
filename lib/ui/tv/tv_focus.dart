// Remote-control navigation for TV mode (Android TV phase, step T3, 0.2.0).
//
// A TV has no touchscreen and no mouse: everything is done with the remote's arrow keys and its
// OK button. Flutter already moves focus with the arrow keys and lets every tap-able widget take
// focus, so what TV mode adds here is:
//  * [TvFocus]: focus is always drawn (not only after a key press), the remote's OK / Select and
//    a game controller's A button press the focused thing, and something has focus as soon as the
//    app opens, so the first arrow press goes somewhere;
//  * [tvTheme]: a clear highlight in the theme's accent colour on whatever has focus, because
//    Material's own focus shading is made for a desk, not for a sofa;
//  * [TvRegion]: keeps the arrow keys inside one part of the screen (the sidebar, the page, the
//    player bar) until they reach its edge, so focus doesn't jump about. Only what's on screen
//    counts: not a page covered by the one opened over it (22 Oct fix: on the TV, Settings opens
//    each page over the list, and ↓ went on into the hidden list, so OK opened About), and lists
//    scroll to keep the focused item in view.
// Settings › Appearance › TV mode decides when it's on (AppearanceSettings.tvLayout). With it off,
// TvFocus and tvTheme step aside. The regions stay either way (so switching TV mode doesn't reset
// open pages); on a computer they only mean Tab finishes the sidebar before moving to the page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tv_sounds.dart';

/// The remote's OK button and its equivalents. Enter and Space already press things in Flutter;
/// Select (most TV remotes) and a game controller's A are added for TV mode.
const tvActivateKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
];

class TvFocus extends StatefulWidget {
  const TvFocus({super.key, required this.enabled, required this.child, this.sounds = false});

  final bool enabled;
  final Widget child;

  /// Sounds as the remote moves around and presses things (0.2.5, services/tv_sounds.dart).
  final bool sounds;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(TvFocus old) {
    super.didUpdateWidget(old);
    if (old.enabled != widget.enabled) _apply();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_soundFor);
    FocusManager.instance.removeListener(_focusChanged);
    if (widget.enabled) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    super.dispose();
  }

  /// Plays the sound for a remote press (only watching: the press carries on as usual). An arrow
  /// sounds once the frame after it has moved focus somewhere new, so a press at a list's edge, or
  /// one that moves through a video, is silent.
  bool _soundFor(KeyEvent e) {
    if (!widget.enabled || !widget.sounds || e is KeyUpEvent) return false;
    final k = e.logicalKey;
    final arrow = switch (k) {
      LogicalKeyboardKey.arrowUp => TvSound.up,
      LogicalKeyboardKey.arrowDown => TvSound.down,
      LogicalKeyboardKey.arrowLeft => TvSound.left,
      LogicalKeyboardKey.arrowRight => TvSound.right,
      _ => null,
    };
    if (arrow != null) {
      final before = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = FocusManager.instance.primaryFocus;
        if (mounted && now != null && now != before) TvSounds.play(arrow);
      });
      WidgetsBinding.instance.scheduleFrame();
    } else if (e is KeyDownEvent && tvActivateKeys.contains(k)) {
      TvSounds.play(TvSound.select);
    } else if (e is KeyDownEvent && (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape)) {
      TvSounds.play(TvSound.back);
    }
    return false;
  }

  void _apply() {
    HardwareKeyboard.instance.removeHandler(_soundFor);
    if (widget.enabled) HardwareKeyboard.instance.addHandler(_soundFor);
    FocusManager.instance.highlightStrategy =
        widget.enabled ? FocusHighlightStrategy.alwaysTraditional : FocusHighlightStrategy.automatic;
    FocusManager.instance.removeListener(_focusChanged);
    if (widget.enabled) {
      FocusManager.instance.addListener(_focusChanged);
      _focusChanged();
    }
  }

  /// When focus lands on a page with nothing inside it focused (the app opening, a page being
  /// opened or closed), give the page's first item focus once it's drawn, the way the first arrow
  /// press would. On a TV something must always have focus, or the remote does nothing visible.
  void _focusChanged() {
    final current = FocusManager.instance.primaryFocus;
    if (current != null && current is! FocusScopeNode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.enabled) return;
      final now = FocusManager.instance.primaryFocus;
      if (now != null && now is! FocusScopeNode) return; // something got focus meanwhile
      final scope = now as FocusScopeNode? ?? FocusManager.instance.rootScope;
      // Back on a page that had something focused: give it back. Otherwise its first item.
      final remembered = scope.focusedChild;
      if (remembered != null && remembered.canRequestFocus && remembered.context != null) {
        remembered.requestFocus();
      } else {
        scope.focusInDirection(TraversalDirection.down);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = _TvOn(on: widget.enabled, child: widget.child);
    if (!widget.enabled) return child;
    // Directional navigation (step 7): what a TV is. Sliders then move with ← → and let ↑ ↓ leave
    // (in the usual mode ↑ ↓ change them, so the remote was stuck on one).
    final media = MediaQuery.maybeOf(context);
    return Shortcuts(
      shortcuts: {for (final k in tvActivateKeys) SingleActivator(k): const ActivateIntent()},
      child: media == null ? child : MediaQuery(data: media.copyWith(navigationMode: NavigationMode.directional), child: child),
    );
  }
}

/// Whether TV mode is on, for [TvRegion].
class _TvOn extends InheritedWidget {
  const _TvOn({required this.on, required super.child});
  final bool on;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_TvOn>()?.on ?? false;

  @override
  bool updateShouldNotify(_TvOn old) => old.on != on;
}

/// Whether TV mode is on where [context] is (the seek preview's remote control, 0.2.0).
bool tvModeOf(BuildContext context) => _TvOn.of(context);

/// One part of the screen the arrow keys stay inside (the sidebar, the page, the player bar).
///
/// In TV mode an arrow press first looks for the nearest item in that direction inside this
/// region; only when there's none (the region's edge) does it cross to the next region, the usual
/// way. Flutter on its own picks the nearest item on the whole screen, so a step down from an
/// album could land in the sidebar instead of on the button under it.
class TvRegion extends StatefulWidget {
  const TvRegion({super.key, required this.child});

  final Widget child;

  @override
  State<TvRegion> createState() => _TvRegionState();
}

class _TvRegionState extends State<TvRegion> {
  // Holds this region's items (skipTraversal: the region itself is never focused).
  final _node = FocusNode(debugLabel: 'TvRegion', skipTraversal: true, canRequestFocus: false);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = _TvOn.of(context);
    return FocusTraversalGroup(
      child: Actions(
        actions: {DirectionalFocusIntent: _RegionArrowAction(_node, () => tv)},
        child: Focus(focusNode: _node, child: widget.child),
      ),
    );
  }
}

/// An arrow press inside a [TvRegion] (see there). Outside TV mode it does exactly what Flutter
/// would have done.
class _RegionArrowAction extends DirectionalFocusAction {
  _RegionArrowAction(this.region, this.tv);

  final FocusNode region;
  final bool Function() tv;

  @override
  void invoke(DirectionalFocusIntent intent) {
    final current = FocusManager.instance.primaryFocus;
    if (tv() && current != null && current.context != null) {
      final d = intent.direction;
      final from = current.rect;
      final here = [for (final n in region.traversalDescendants) if (n != current && tvCanGo(n)) n];
      // The other parts of the screen (the sidebar, the player bar), worked out only if needed.
      // Flutter's own step only looks inside the page that's open, so it can't leave it.
      List<FocusNode> elsewhere() {
        final inHere = here.toSet()..add(current);
        return [
          for (final n in FocusManager.instance.rootScope.traversalDescendants)
            if (!inHere.contains(n) && !_isWithin(n, region) && tvCanGo(n)) n,
        ];
      }

      // In order: straight ahead in this part of the screen (along a row for ← →); straight ahead
      // in the next part (the page's edge to the sidebar); anything that way in this part (the
      // other column of a two-pane page); anything that way at all.
      //
      // ↑ ↓ only cross to another part of the screen in line with what has focus (0.2.5): ↑ from
      // a page's Play button opened the menu on Music, the item nearest above it, though Videos
      // was the page showing. With nothing that way, ↑ ↓ stay put, as on other TV apps; ← is the
      // way into the menu.
      final vertical = d == TraversalDirection.up || d == TraversalDirection.down;
      var next = nearestInDirection(from, d, here);
      List<FocusNode>? others;
      next ??= nearestInDirection(from, d, others ??= elsewhere(), inLineOnly: vertical);
      next ??= nearestInDirection(from, d, here, levelOnly: false);
      if (!vertical) next ??= nearestInDirection(from, d, others ??= elsewhere(), levelOnly: false);
      if (next != null) {
        tvFocusOn(next, d);
        return;
      }
      if (vertical) return;
    }
    super.invoke(intent);
  }

  static bool _isWithin(FocusNode n, FocusNode region) => n.ancestors.contains(region);
}

/// Whether the remote can move to [n]: it takes focus, and it's on the page that's showing, not
/// one covered by another page or a dialog.
bool tvCanGo(FocusNode n) {
  final context = n.context;
  if (!n.canRequestFocus || n.skipTraversal || context == null || !context.mounted) return false;
  final route = ModalRoute.of(context);
  return route == null || route.isCurrent;
}

/// Gives [n] focus and scrolls it into view ([tvReveal]).
void tvFocusOn(FocusNode n, TraversalDirection direction) {
  n.requestFocus();
  final context = n.context;
  if (context != null) tvReveal(context);
}

/// Scrolls whatever [context] is in so it's comfortably on screen (0.2.5). Up and down, it's
/// kept between [tvRevealBand]'s edges, and moved to the nearer edge when it leaves them, so the
/// focused row is never on the screen's bottom edge under the hint bubble, and you can see what
/// comes next (28 Oct review: lists only scrolled until the focused item touched the edge). Near
/// the start of a page, the page goes all the way back up, so its title and headings show.
/// Sideways (a row of tiles), only as far as it takes to show the item.
void tvReveal(BuildContext context) {
  final target = context.findRenderObject();
  if (target is! RenderBox || !target.attached || !target.hasSize) return;
  final item = MatrixUtils.transformRect(target.getTransformTo(null), Offset.zero & target.size);
  var at = context;
  var scrollable = Scrollable.maybeOf(at);
  while (scrollable != null) {
    final object = at.findRenderObject();
    final box = scrollable.context.findRenderObject();
    final position = scrollable.position;
    if (object != null && box is RenderBox && box.hasSize && position.hasContentDimensions) {
      final view = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
      final vertical = position.axis == Axis.vertical;
      final (start, end, viewStart, viewEnd) =
          vertical ? (item.top, item.bottom, view.top, view.bottom) : (item.left, item.right, view.left, view.right);
      final space = (viewEnd - viewStart) - (end - start);
      double? alignment;
      if (!vertical || space <= 0) {
        if (start < viewStart) alignment = 0;
        if (end > viewEnd) alignment = 1;
      } else if (start - viewStart + position.pixels - position.minScrollExtent + (end - start) <= (viewEnd - viewStart) * 0.85) {
        // Near the top of the page (it fits well on screen with the page at its very top): show
        // the page from the top.
        if (position.pixels > position.minScrollExtent) {
          position.jumpTo(position.minScrollExtent);
        }
      } else {
        final now = (start - viewStart) / space;
        if (now < tvRevealBand.$1) alignment = tvRevealBand.$1;
        if (now > tvRevealBand.$2) alignment = tvRevealBand.$2;
      }
      if (alignment != null) {
        // At once, as before: a press that comes while a list is still gliding would measure
        // where things are mid-way (found by tests: ← then skipped past buttons).
        position.ensureVisible(object, alignment: alignment, targetRenderObject: identical(object, target) ? null : target);
      }
    }
    at = scrollable.context;
    scrollable = Scrollable.maybeOf(at);
  }
}

/// Where up and down keep what has focus, as a share of the space it can move in: 0 has it at
/// the top of its list, 1 at the bottom.
const tvRevealBand = (0.1, 0.6);

/// Moves focus to the first thing (top left) that can take it inside [within], scrolled into
/// view. For a pane whose content was just changed from elsewhere (Settings' list and page).
/// Returns false if there's nothing there.
bool tvFocusFirstIn(FocusNode within) {
  // Only things that take focus themselves: not the pages' focus scopes, which cover the whole
  // page and would always come first.
  final all = [for (final n in within.traversalDescendants) if (n is! FocusScopeNode && tvCanGo(n)) n];
  if (all.isEmpty) return false;
  // The top row, then its left-most: things within a few pixels of the top count as one row (a
  // title row's tabs and its taller Sort button; a grid's first tiles and the A–Z strip beside
  // them).
  const sameRow = 14.0;
  final top = all.map((n) => n.rect.top).reduce((a, b) => a < b ? a : b);
  all
    ..retainWhere((n) => n.rect.top <= top + sameRow)
    ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
  tvFocusOn(all.first, TraversalDirection.up);
  return true;
}

/// The node in [candidates] nearest to [from] in [direction], or null if none lies that way.
/// Left / Right only consider items level with [from] ([levelOnly]; false: any that way); Up /
/// Down prefer items in line with it (overlapping it across the direction of travel) over ones
/// off to the side. Nearer beats further.
/// [inLineOnly]: only items in line with [from], whichever way (crossing to another part of the
/// screen with ↑ ↓).
FocusNode? nearestInDirection(Rect from, TraversalDirection direction, Iterable<FocusNode> candidates,
    {bool levelOnly = true, bool inLineOnly = false}) {
  const slack = 1.0; // rounding
  FocusNode? best;
  var bestScore = double.infinity;
  for (final n in candidates) {
    final r = n.rect;
    final (ahead, along, across) = switch (direction) {
      TraversalDirection.down => (r.top >= from.bottom - slack, r.top - from.bottom, _gap(r.left, r.right, from.left, from.right)),
      TraversalDirection.up => (r.bottom <= from.top + slack, from.top - r.bottom, _gap(r.left, r.right, from.left, from.right)),
      TraversalDirection.right => (r.left >= from.right - slack, r.left - from.right, _gap(r.top, r.bottom, from.top, from.bottom)),
      TraversalDirection.left => (r.right <= from.left + slack, from.left - r.right, _gap(r.top, r.bottom, from.top, from.bottom)),
    };
    if (!ahead) continue;
    // Left / Right move along a row: only items level with this one. At the row's end the press
    // crosses to the next region (from the page to the sidebar). Up / Down may step to the
    // nearest row even when it doesn't line up exactly (a button under a row of cards).
    final sideways = direction == TraversalDirection.left || direction == TraversalDirection.right;
    if (sideways && levelOnly && across > 0) continue;
    if (inLineOnly && across > 0) continue;
    // In line counts most; then distance.
    final score = (across > 0 ? 100000.0 : 0.0) + along.clamp(0, double.infinity) + 2 * across;
    if (score < bestScore) {
      bestScore = score;
      best = n;
    }
  }
  return best;
}

/// How far apart two ranges [a1, a2] and [b1, b2] are (0 when they overlap).
double _gap(double a1, double a2, double b1, double b2) => a2 < b1 ? b1 - a2 : (b2 < a1 ? a1 - b2 : 0);

/// [theme] with a clear focus highlight in [accent] for TV mode: cards, rows and every kind of
/// button get a strong accent shade while they have focus. Pressing shades a little; there's no
/// hover on a TV.
ThemeData tvTheme(ThemeData theme, Color accent) {
  final focused = accent.withValues(alpha: 0.45);
  final pressed = accent.withValues(alpha: 0.3);
  final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.focused)) return focused;
    if (states.contains(WidgetState.pressed)) return pressed;
    return null;
  });
  final buttons = ButtonStyle(overlayColor: overlay);
  // A ring in the text colour too (0.2.5): on a button already filled in the accent colour, the
  // accent shade alone didn't show (Settings › Servers' "Add a server" had focus, invisibly).
  final ring = BorderSide(color: theme.colorScheme.onSurface, width: 3);
  ButtonStyle withFocus(ButtonStyle? style) {
    final base = (style ?? const ButtonStyle()).merge(buttons);
    final side = base.side;
    return base.copyWith(
      side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused) ? ring : side?.resolve(states)),
    );
  }

  // Switches: a ring round the track and a clear halo, whichever way they're set.
  final switches = theme.switchTheme;
  return theme.copyWith(
    switchTheme: switches.copyWith(
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? theme.colorScheme.onSurface : switches.trackOutlineColor?.resolve(states)),
      trackOutlineWidth: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? 3 : switches.trackOutlineWidth?.resolve(states)),
      overlayColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
          ? theme.colorScheme.onSurface.withValues(alpha: 0.28)
          : switches.overlayColor?.resolve(states)),
    ),
    focusColor: focused,
    iconButtonTheme: IconButtonThemeData(style: withFocus(theme.iconButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: withFocus(theme.textButtonTheme.style)),
    filledButtonTheme: FilledButtonThemeData(style: withFocus(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: withFocus(theme.outlinedButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: withFocus(theme.elevatedButtonTheme.style)),
  );
}
