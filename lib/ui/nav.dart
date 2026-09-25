import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/book_screen.dart';
import 'screens/playlist_screen.dart';

/// Keeps one Navigator per tab so album/artist pages open inside the content
/// area while the player bar stays put.
class AppNav extends ChangeNotifier {
  static const tabCount = 5; // Home, Search, Library, Books, Settings
  static const libraryTab = 2;
  static const booksTab = 3;
  static const settingsTab = 4;
  final List<GlobalKey<NavigatorState>> keys = List.generate(tabCount, (_) => GlobalKey<NavigatorState>());
  int tab = 0;

  NavigatorState? get current => keys[tab].currentState;

  void selectTab(int i) {
    if (i == tab) {
      // Tapping the active tab again goes back to its root.
      current?.popUntil((r) => r.isFirst);
    } else {
      tab = i;
      notifyListeners();
    }
  }

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

  void push(Widget page) => current?.push(MaterialPageRoute(builder: (_) => page));

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
}
