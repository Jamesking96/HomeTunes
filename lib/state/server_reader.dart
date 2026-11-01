// What Settings › Servers needs from something that reads a server into a tab (0.2.7): Jellyfin
// servers' videos (server_videos.dart) and Audiobookshelf servers' audiobooks (server_books.dart).
// A server's card shows [statusFor] with a green or red dot, and its ⋮ menu has Sync now,
// Libraries… and Sign out on this device.
import 'package:flutter/foundation.dart';

import 'servers_model.dart';

/// One of a server's libraries, as Libraries… lists it.
typedef ServerLibraryChoice = ({String id, String name});

abstract class ServerReader implements Listenable {
  /// What it reads (Videos, Audiobooks).
  MediaKind get readsKind;

  /// Whether it reads [s] (the right kind of server, switched on for [readsKind]).
  bool reads(ServerEntry s);

  /// A line about how the server is doing ("Signed in as … · 58 books · read 5 min ago").
  String statusFor(ServerEntry s);

  /// Green (fine), red (a problem) or no dot.
  bool? okFor(ServerEntry s);

  bool isSyncing(ServerEntry s);
  Future<void> sync(ServerEntry s);

  /// Signs out of [s] on this device (the next read signs in again with the saved password).
  Future<void> signOut(ServerEntry s);

  /// The server's libraries of the kind it reads (as last read).
  List<ServerLibraryChoice> libraryChoicesOf(ServerEntry s);
  bool isLibraryShown(ServerEntry s, String id);
  Future<void> setLibraryShown(ServerEntry s, String id, bool shown);
}
