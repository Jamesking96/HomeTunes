import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'screens/album_screen.dart';
import 'screens/artist_screen.dart';
import 'screens/playlist_screen.dart';

/// Keeps one Navigator per tab so album/artist pages open inside the content
/// area while the player bar stays put.
class AppNav extends ChangeNotifier {
  static const tabCount = 4; // Home, Search, Library, Settings
  static const settingsTab = 3;
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

  void push(Widget page) => current?.push(MaterialPageRoute(builder: (_) => page));

  void openAlbum(Album a) => push(AlbumScreen(albumKey: a.key));
  void openArtist(String name) => push(ArtistScreen(name: name));
  void openPlaylist(Playlist p) => push(PlaylistScreen(playlistId: p.id));
  void openLiked() => push(const PlaylistScreen.liked());
}
