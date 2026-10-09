// LibraryModel and its settings groups, for a Provider list (refactor phase 9, 9 Oct 2026). Screens
// watch the settings group they use (Settings › Playback watches PlaybackSettings, the sidebar
// LayoutSettings…) rather than LibraryModel, which only passes on changes to the folders and the
// server. main.dart and the widget tests use this so every group is always there to watch.
import 'package:provider/provider.dart';

import '../state/library_model.dart';
import '../state/settings/settings_groups.dart';

/// [library], then each of its settings groups, each as its own provider. (Each is given its type:
/// left to inference, the list's type would make them all plain ChangeNotifier providers.)
List<ChangeNotifierProvider> libraryProviders(LibraryModel library) {
  final s = library.settings;
  return [
    ChangeNotifierProvider<LibraryModel>.value(value: library),
    ChangeNotifierProvider<FolderSettings>.value(value: s.folders),
    ChangeNotifierProvider<ServerSettings>.value(value: s.server),
    ChangeNotifierProvider<OnlineSettings>.value(value: s.online),
    ChangeNotifierProvider<PlaybackSettings>.value(value: s.playback),
    ChangeNotifierProvider<ListeningSettings>.value(value: s.listening),
    ChangeNotifierProvider<VideoSettings>.value(value: s.video),
    ChangeNotifierProvider<AppearanceSettings>.value(value: s.appearance),
    ChangeNotifierProvider<LayoutSettings>.value(value: s.layout),
  ];
}
