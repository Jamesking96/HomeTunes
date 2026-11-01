// Audiobooks that come from an Audiobookshelf server (0.2.7): what LibraryModel and the player
// need from whatever brings them in (state/server_books.dart), so neither has to know the server.
//
// Each of a server book's audio files is a Track with the id `abs:<server>:<item>:<ino>` (the
// server being its entry in Settings › Servers, the item the book on the server and the ino the
// file in it), so two servers can never clash and nothing else's id looks like one. They have no
// path: [RemoteBookSource.streamUrlFor] gives the address to play. All the files of one item make
// one book (book_index.dart's bookKey), with the id `book:abs:<server>:<item>`.
import '../models/track.dart';

/// True for a book file that comes from an Audiobookshelf server.
bool isRemoteBookId(String id) => id.startsWith('abs:');

/// The id of file [ino] of item [item] on server [server].
String remoteBookTrackId(String server, String item, String ino) => 'abs:$server:$item:$ino';

/// `abs:<server>:<item>:<ino>` → (server, item, ino), or null.
({String server, String item, String ino})? remoteBookParts(String id) {
  if (!isRemoteBookId(id)) return null;
  final parts = id.substring(4).split(':');
  if (parts.length != 3 || parts.any((x) => x.isEmpty)) return null;
  return (server: parts[0], item: parts[1], ino: parts[2]);
}

/// The book key of a server book's file (`abs:<server>:<item>`), or null.
String? remoteBookKey(String trackId) {
  final p = remoteBookParts(trackId);
  return p == null ? null : 'abs:${p.server}:${p.item}';
}

/// The book id of item [item] on server [server].
String remoteBookId(String server, String item) => 'book:abs:$server:$item';

/// Where to download a server book's file from: its address, the headers it needs (the sign-in)
/// and the file type.
typedef RemoteBookDownload = ({String url, Map<String, String> headers, String ext});

/// What brings server books in (ServerBooksModel).
abstract class RemoteBookSource {
  /// Makes sure [t] can be played now (a fresh sign-in when the old one is about to run out).
  Future<void> prepare(Track t);

  /// The address to play [t] from, or null when it can't be played now ([problemFor] says why).
  String? streamUrlFor(Track t);

  /// Where to download [t] from, or null.
  Future<RemoteBookDownload?> downloadRequest(Track t);

  /// Why [t] can't be played or downloaded now, or null.
  String? problemFor(Track t);
}
