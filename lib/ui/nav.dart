// App navigation: which tab is showing, and how pages open inside it.
//
// Each of the six tabs (Home, Search, Library, Books, Videos, Settings) has its own Navigator, so
// opening an album on the Library tab and then switching to Books and back keeps your place.
// Pages open inside the content area only, so the player bar / mini player never moves.
// Created once in main.dart and provided to the whole app; Shell builds the Navigators using
// [AppNav.keys], and screens call openAlbum / openBook / openSettings etc. to move around.
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/video_item.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/book_screen.dart';
import 'screens/playlist_screen.dart';
import 'screens/video_player_screen.dart';

/// Keeps one Navigator per tab so album/artist pages open inside the content
/// area while the player bar stays put.
class AppNav extends ChangeNotifier {
  static const tabCount = 6; // Home, Search, Library, Books, Videos, Settings
  static const libraryTab = 2;
  static const booksTab = 3;
  static const videosTab = 4; // 0.1.32
  static const settingsTab = 5;
  /// One key per tab, so we can reach each tab's Navigator from outside the widget tree.
  final List<GlobalKey<NavigatorState>> keys = List.generate(tabCount, (_) => GlobalKey<NavigatorState>());
  /// The tab currently showing (0 = Home).
  int tab = 0;

  /// The Navigator of the tab on screen (null if it hasn't been built yet).
  NavigatorState? get current => keys[tab].currentState;

  /// Switches to tab [i], or pops back to the tab's first page if it's already showing.
  void selectTab(int i) {
    if (i == tab) {
      // Tapping the active tab again goes back to its root.
      current?.popUntil((r) => r.isFirst);
    } else {
      tab = i;
      notifyListeners();
    }
  }

  // A "please open this settings page" note left by openSettings, waiting for the Settings
  // screen to pick it up (it may not be built yet when the request is made).
  ({String page, String? setting})? _settingsRequest;

  /// Opens Settings at one of its pages (a `SettingsPage` name), optionally
  /// scrolled to one setting. The Settings screen picks the request up.
  void openSettings(String page, {String? setting}) {
    _settingsRequest = (page: page, setting: setting);
    tab = settingsTab;
    notifyListeners();
  }

  /// The pending [openSettings] request, cleared once taken.
  ({String page, String? setting})? takeSettingsRequest() {
    final r = _settingsRequest;
    _settingsRequest = null;
    return r;
  }

  /// Opens [page] on top of the current tab's stack.
  void push(Widget page) => current?.push(MaterialPageRoute(builder: (_) => page));

  // Shortcuts used all over the app. Screens are opened by id/key rather than by passing the
  // object itself, so they always show the latest data after a rescan or edit.
  void openAlbum(Album a) => push(AlbumScreen(albumKey: a.key));
  void openArtist(String name) => push(ArtistScreen(name: name));
  void openPlaylist(Playlist p) => push(PlaylistScreen(playlistId: p.id));
  void openLiked() => push(const PlaylistScreen.liked());

  /// Opens a book's page on the Books tab.
  void openBook(Book b) {
    if (tab != booksTab) {
      tab = booksTab;
      notifyListeners();
    }
    // The Books tab's navigator may not exist until the tab is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => push(BookScreen(bookId: b.id)));
  }

  /// Opens a video's player page on the Videos tab (0.1.32).
  void openVideo(VideoItem v) {
    if (tab != videosTab) {
      tab = videosTab;
      notifyListeners();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => push(VideoPlayerScreen(videoId: v.id)));
  }
}
