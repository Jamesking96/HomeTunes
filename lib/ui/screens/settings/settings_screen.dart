// The Settings tab: a list of settings pages with a search box on top.
//
// It's the root page of the Settings tab's Navigator (see shell.dart). On wide windows the list
// sits on the left and the chosen page on the right; on phones tapping a page pushes it as its
// own screen. Other screens can jump straight to a page via AppNav.openSettings, which leaves a
// request that this screen picks up in [_SettingsScreenState._takeRequest]. The pages themselves
// live in the other files in this folder; the list of pages and search words in
// settings_catalog.dart.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/music_access_banner.dart';
import 'about_settings.dart';
import 'audiobook_settings.dart';
import 'backup_settings.dart';
import 'edits_settings.dart';
import 'library_settings.dart';
import 'online_settings.dart';
import 'playback_settings.dart';
import 'server_settings.dart';
import 'settings_catalog.dart';
import 'settings_widgets.dart';
import 'sleep_settings.dart';

/// The contents of one settings page.
Widget settingsPageBody(SettingsPage page) => switch (page) {
      SettingsPage.library => const LibrarySettings(),
      SettingsPage.playback => const PlaybackSettings(),
      SettingsPage.sleepTimer => const SleepTimerSettings(),
      SettingsPage.audiobooks => const AudiobookSettings(),
      SettingsPage.onlineLookups => const OnlineLookupSettings(),
      SettingsPage.server => const ServerSettings(),
      SettingsPage.edits => const EditsSettings(),
      SettingsPage.backup => const BackupSettings(),
      SettingsPage.about => const AboutSettings(),
    };

/// Settings: a list of pages with a search box. Wide windows show the list and
/// the open page side by side; phones open each page on its own.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Narrower than this, the list and the page don't fit side by side.
  static const twoPaneWidth = 760.0;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  String _query = ''; // the trimmed search text; empty means "show the list of pages"
  SettingsPage _page = SettingsPage.library; // the page open on the right (wide only)
  String? _highlight; // the setting to scroll to and light up on that page
  int _opened = 0; // makes the page start fresh (and scroll) each time a setting is picked
  bool _wide = false; // set during build from the available width

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Shows [page] (and optionally lights up [setting] on it): in the right-hand pane when wide,
  /// otherwise as a new screen on the Settings tab.
  void _open(SettingsPage page, [String? setting]) {
    if (_wide) {
      setState(() {
        _page = page;
        _highlight = setting;
        _opened++;
      });
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _SettingsPageScreen(page: page, highlight: setting),
      ));
    }
  }

  /// Another screen asked for a particular page (e.g. "Add music" on Home).
  void _takeRequest(AppNav nav) {
    final request = nav.takeSettingsRequest();
    if (request == null) return;
    final page = SettingsPage.byName(request.page);
    if (page == null) return;
    // We're in the middle of build here, so act after the frame: close any settings page
    // already open on a phone, then open the requested one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      _open(page, request.setting);
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: LayoutBuilder(builder: (context, box) {
        _wide = box.maxWidth >= SettingsScreen.twoPaneWidth;
        // Checked on every build: AppNav rebuilds us (we watch it) when a request arrives.
        _takeRequest(nav);
        // Phone: one scrolling list of the banner, search box and pages.
        if (!_wide) {
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            const MusicAccessBanner(),
            _searchField(),
            ..._entries(),
          ]);
        }
        // Wide: the list (300 px) on the left, then the open page with its title on the right.
        return Column(children: [
          const MusicAccessBanner(),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 300,
                child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [_searchField(), ..._entries()]),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    // Lines up with the page's own padding.
                    child: Text(_page.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    // Keeps switches and drop-downs close to their labels on big screens.
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        // The key changes each time a page/setting is opened, so the page is
                        // rebuilt from scratch and the highlight runs again.
                        child: SettingsHighlight(
                          key: ValueKey('${_page.name}/$_opened'),
                          id: _highlight,
                          child: settingsPageBody(_page),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]);
      }),
    );
  }

  /// The "Search settings" box, with a clear button once something is typed.
  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: TextField(
          key: const ValueKey('settings-search'),
          controller: _search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search settings',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      );

  /// The rows under the search box: search results while searching, otherwise every page.
  List<Widget> _entries() {
    if (_query.isNotEmpty) {
      final found = searchSettings(_query);
      if (found.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No settings match "$_query"', style: const TextStyle(color: AppColors.textDim)),
          ),
        ];
      }
      return [
        for (final s in found)
          ListTile(
            leading: Icon(s.page.icon),
            title: Text(s.title),
            subtitle: Text(s.page.title),
            onTap: () => _open(s.page, s.id),
          ),
      ];
    }
    // No search: one row per page. On wide windows the open page is shown as selected.
    return [
      for (final p in SettingsPage.values)
        ListTile(
          leading: Icon(p.icon),
          title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(p.summary, maxLines: _wide ? 1 : 2, overflow: TextOverflow.ellipsis),
          dense: _wide,
          selected: _wide && p == _page,
          selectedTileColor: AppColors.surface,
          trailing: _wide ? null : const Icon(Icons.chevron_right),
          onTap: () => _open(p),
        ),
    ];
  }
}

/// One settings page on its own (phones).
class _SettingsPageScreen extends StatelessWidget {
  final SettingsPage page;
  final String? highlight;
  const _SettingsPageScreen({required this.page, this.highlight});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(page.title)),
        body: SettingsHighlight(id: highlight, child: settingsPageBody(page)),
      );
}
