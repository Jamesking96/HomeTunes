// The TV's Settings screen (0.2.0, step 7 of the TV interface; mockup "Settings"). The pages are
// listed on the left; the one the remote is on shows on the right straight away, as the tabs do
// elsewhere. → (or OK) goes into the page, ← from its left edge comes back to the list. The pages
// themselves are the usual ones (settings_screen.dart's [settingsPageBody]); in TV mode their
// parts work with the remote: a choice opens its list (ChoiceTile), a switch flips with OK, a
// slider moves with ← → (and ↑ ↓ leave it), and a text box opens the TV keyboard (TvTextField).
//
// "Search settings" at the top of the list types with the keyboard and lists what matches;
// choosing one opens its page with the remote on it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../nav.dart';
import '../screens/settings/settings_catalog.dart';
import '../screens/settings/settings_screen.dart' show settingsPageBody;
import '../screens/settings/settings_widgets.dart';
import '../theme.dart';
import '../widgets/music_access_banner.dart';
import 'tv_browse.dart';
import 'tv_focus.dart';
import 'tv_keyboard.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

const tvSettingsHints = <TvHint>[('OK', 'Choose or switch'), ('→', 'Into the page'), ('←', 'Back / Menu')];

/// Settings pages that mean nothing on a TV, left out of its list and search (0.2.5, the user's
/// choice on 28 Oct): Your edits writes tags into music files, a job for the PC.
const tvHiddenPages = {SettingsPage.edits};

/// Single settings left out on a TV (the pages hide them too, with [tvModeOf]): swiping is for
/// touch screens.
const tvHiddenSettings = {'swipe-to-skip', 'write-tags', 'write-backup'};

class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  State<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends State<TvSettingsScreen> {
  SettingsPage _page = SettingsPage.library;
  String? _highlight;
  int _opened = 0;
  Timer? _settle;

  final _pane = FocusNode(debugLabel: 'tv settings page', skipTraversal: true, canRequestFocus: false);
  final _rows = {for (final p in SettingsPage.values) p: FocusNode(debugLabel: 'tv settings ${p.name}')};

  @override
  void dispose() {
    _settle?.cancel();
    _pane.dispose();
    for (final n in _rows.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Shows [page] on the right (lighting up [setting]); [into]: the remote goes into it.
  void _show(SettingsPage page, {String? setting, bool into = false}) {
    _settle?.cancel();
    if (page != _page || setting != null) {
      setState(() {
        _page = page;
        _highlight = setting;
        _opened++;
      });
    }
    if (into) _enter(setting);
  }

  /// Moves the remote into the page: onto [setting] if given (once it has scrolled there), else its top.
  void _enter([String? setting]) {
    // A frame may not be coming (the page didn't change), so ask for one.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (setting != null) {
        // SettingTarget scrolls itself into view (300 ms); then the first thing in it.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        final target = _findTarget(setting);
        if (target != null) {
          final box = target.findRenderObject() as RenderBox?;
          if (box != null && box.attached) {
            final r = box.localToGlobal(Offset.zero) & box.size;
            final inside = [
              for (final n in _pane.traversalDescendants)
                if (n is! FocusScopeNode && tvCanGo(n) && r.overlaps(n.rect)) n,
            ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
            if (inside.isNotEmpty) {
              tvFocusOn(inside.first, TraversalDirection.down);
              return;
            }
          }
        }
      }
      tvFocusFirstIn(_pane);
    });
  }

  Element? _findTarget(String id) {
    final root = _pane.context;
    if (root == null) return null;
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (e.widget.key == ValueKey('setting:$id')) {
        found = e;
        return;
      }
      e.visitChildElements(visit);
    }

    (root as Element).visitChildElements(visit);
    return found;
  }

  /// Another screen asked for a page ("Add music folders" on Music): open it with the remote in it.
  void _takeRequest(AppNav nav) {
    final request = nav.takeSettingsRequest();
    if (request == null) return;
    final page = SettingsPage.byName(request.page);
    if (page == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _show(page, setting: request.setting, into: true);
    });
  }

  Future<void> _search() async {
    final typed = await showTvTextInput(
      context,
      title: 'Search settings',
      hint: 'A word from the setting: gap, theme, folder…',
    );
    if (typed == null || typed.trim().isEmpty || !mounted) return;
    final found = [for (final s in searchSettings(typed)) if (!tvHiddenPages.contains(s.page) && !tvHiddenSettings.contains(s.id)) s];
    await showTvOptions(
      context,
      title: found.isEmpty ? 'No settings match "${typed.trim()}"' : 'Settings matching "${typed.trim()}"',
      options: [
        for (final s in found)
          TvOption(s.title, s.page.icon, () => _show(s.page, setting: s.id, into: true), subtitle: s.page.title),
        if (found.isEmpty) TvOption('Search again', Icons.search, _search),
      ],
    );
  }

  /// → from the list: into the page showing (the one the remote is on), at its top.
  KeyEventResult _listKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final on = _rows.entries.where((r) => r.value.hasPrimaryFocus).map((r) => r.key).firstOrNull;
    _show(on ?? _page, into: true);
    return KeyEventResult.handled;
  }

  /// ← at the page's left edge: back to its row in the list (not whichever row is level with it).
  KeyEventResult _paneKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || e.logicalKey != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
    final current = FocusManager.instance.primaryFocus;
    if (current == null || current.context == null) return KeyEventResult.ignored;
    final inPane = [
      for (final n in _pane.traversalDescendants)
        if (n != current && tvCanGo(n)) n,
    ];
    if (nearestInDirection(current.rect, TraversalDirection.left, inPane) != null) return KeyEventResult.ignored;
    tvFocusOn(_rows[_page]!, TraversalDirection.left);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _takeRequest(context.watch<AppNav>());
    final theme = Theme.of(context);
    return TvPageHints(
      tab: AppNav.settingsTab,
      hints: tvSettingsHints,
      child: TvPage(
        title: 'Settings',
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 250,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _listKey,
                child: ListView(
                  key: const ValueKey('tv-settings-pages'),
                  padding: const EdgeInsets.fromLTRB(4, 4, 8, 24),
                  clipBehavior: Clip.none,
                  children: [
                    _ListRow(
                      key: const ValueKey('tv-settings-search'),
                      label: 'Search settings',
                      icon: Icons.search,
                      onPressed: _search,
                    ),
                    const SizedBox(height: 8),
                    for (final p in SettingsPage.values)
                      if (!tvHiddenPages.contains(p))
                      _ListRow(
                        key: ValueKey('tv-settings-${p.name}'),
                        focusNode: _rows[p],
                        label: p.title,
                        selected: p == _page,
                        onFocus: () {
                          // Resting on a page shows it; passing over doesn't rebuild every page.
                          _settle?.cancel();
                          _settle = Timer(const Duration(milliseconds: 250), () {
                            if (mounted) _show(p);
                          });
                        },
                        onPressed: () => _show(p, into: true),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                    child: Text(
                      _page.title,
                      key: const ValueKey('tv-settings-title'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  if (_page == SettingsPage.library) const MusicAccessBanner(),
                  Expanded(
                    child: Theme(
                      // Bigger rows with rounded corners, so the focus shade reads from the sofa.
                      data: theme.copyWith(
                        listTileTheme: theme.listTileTheme.copyWith(
                          minVerticalPadding: 10,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      child: Focus(
                        focusNode: _pane,
                        onKeyEvent: _paneKey,
                        child: SettingsHighlight(
                          key: ValueKey('${_page.name}/$_opened'),
                          id: _highlight,
                          child: settingsPageBody(_page),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in the list of pages: the page showing is tinted in the accent colour.
class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected = false,
    this.focusNode,
    this.onFocus,
  });
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: TvPressable(
        focusNode: focusNode,
        semanticLabel: label,
        onPressed: onPressed,
        onFocusChange: (f) {
          if (f) onFocus?.call();
        },
        builder: (context, focused) => TvFocusFrame(
          focused: focused,
          radius: 10,
          grow: false,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            color: focused
                ? AppColors.surfaceHigh
                : selected
                ? AppColors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: AppColors.textDim), const SizedBox(width: 10)],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected || focused ? FontWeight.w600 : FontWeight.w400,
                      color: focused ? Colors.white : (selected ? AppColors.accent : const Color(0xFFC9CDD4)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
