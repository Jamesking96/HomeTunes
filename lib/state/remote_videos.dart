// Videos that come from a server rather than a video folder (0.2.1): what VideoLibraryModel and
// the video page need from whatever brings them in (state/server_videos.dart for Jellyfin), so
// neither has to know which kind of server it is.
//
// A server video's id is `jf:<server>:<item>` (the server being its entry in Settings › Servers),
// as the design notes planned for 0.1.46, so two servers can never clash and a local file's id
// (`video:<path>`) never looks like one. Its `path` is a made-up `jellyfin://…` name ending in the
// file's real extension (so the Format detail and the Source filter work); it is never opened as a
// file: [RemoteVideoSource.streamFor] gives the address to play, with the sign-in in headers.
import '../models/video_item.dart';

/// True for a video that comes from a server.
bool isRemoteVideoId(String id) => id.startsWith('jf:');

/// The server entry a server video belongs to (`jf:<server>:<item>` → `<server>`), or null.
String? remoteServerOf(String id) {
  if (!isRemoteVideoId(id)) return null;
  final rest = id.substring(3);
  final i = rest.indexOf(':');
  return i <= 0 ? null : rest.substring(0, i);
}

/// The item's id on its server (`jf:<server>:<item>` → `<item>`), or null.
String? remoteItemOf(String id) {
  if (!isRemoteVideoId(id)) return null;
  final rest = id.substring(3);
  final i = rest.indexOf(':');
  return i <= 0 || i + 1 >= rest.length ? null : rest.substring(i + 1);
}

/// Where to play a video from: a file, or a server address with the headers it needs.
class VideoAddress {
  /// A file path, or an http(s) address.
  final String uri;

  /// Sent with every request for a server address (the sign-in). Never shown or logged.
  final Map<String, String>? headers;

  /// From a server.
  final bool remote;

  /// The server converts it as it sends it (a copy the device can play), rather than sending the
  /// original. Such a stream can't jump around freely.
  final bool converted;

  /// For a converted stream: where it begins (the server starts it there).
  final Duration? startsAt;

  /// Subtitle files the server keeps beside the video: their addresses (same headers) and a
  /// label ("English (SRT)").
  final List<({String uri, String label, String? language})> subtitles;

  const VideoAddress(
    this.uri, {
    this.headers,
    this.remote = false,
    this.converted = false,
    this.startsAt,
    this.subtitles = const [],
  });
}

/// Whatever brings server videos in (ServerVideosModel), as the Videos tab and player see it.
abstract class RemoteVideoSource {
  /// The address to play [v] from, starting at [start]; with [converted], a copy the server
  /// converts. Null when the server can't be reached or isn't signed in (the reason is in
  /// [problemFor]).
  Future<VideoAddress?> streamFor(VideoItem v, {bool converted = false, Duration? start});

  /// Why [v] can't be played right now, in a sentence, or null.
  String? problemFor(VideoItem v);

  /// The name of the server [v] comes from ("Den"), or null.
  String? serverNameOf(VideoItem v);

  /// The video page started playing [v] at [at].
  void started(VideoItem v, Duration at, {bool converted = false});

  /// Where it's got to (called every few seconds while playing, and on pause).
  void progress(VideoItem v, Duration at, Duration length, {required bool paused});

  /// The video page stopped playing [v] (closed, or moved on to another video) at [at].
  void stopped(VideoItem v, Duration at, Duration length);

  /// The user marked videos watched or not watched.
  void watchedChanged(Iterable<VideoItem> list, bool watched);
}
