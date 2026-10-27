// Where something comes from (0.2.2, step 2 of the Servers & Downloads plan): "On this device",
// "Streamed" (from a server) or "Downloaded" (from a server, with a copy here; downloads arrive in
// step 3, which sets [MediaSources.downloaded]). Every tab's "Show only" sheet has a Source choice
// built from these (music_filters.dart, book_index.dart, video_filters.dart), and the cards and
// rows show a small mark for streamed and downloaded things (ui/widgets/source_mark.dart).
//
// An album, artist, book or collection can be a mix: it has every source its songs or videos
// have, so "Streamed" shows an album with any streamed song in it.
import '../models/track.dart';
import '../models/video_item.dart';
import 'filters.dart';
import 'remote_videos.dart';

/// Where one song, book file or video comes from.
enum MediaSource {
  local('On this device'),
  streamed('Streamed'),
  downloaded('Downloaded');

  final String label;
  const MediaSource(this.label);
}

/// What downloads are kept (set by the downloads in step 3; nothing is downloaded before then).
class MediaSources {
  MediaSources._();

  /// Whether the server song or video [id] has a downloaded copy on this device.
  static bool Function(String id) downloaded = (_) => false;
}

MediaSource sourceOfTrack(Track t) =>
    t.isLocal ? MediaSource.local : (MediaSources.downloaded(t.id) ? MediaSource.downloaded : MediaSource.streamed);

MediaSource sourceOfVideo(VideoItem v) => !isRemoteVideoId(v.id)
    ? MediaSource.local
    : (MediaSources.downloaded(v.id) ? MediaSource.downloaded : MediaSource.streamed);

/// The label the Source filter is under.
const sourceFieldLabel = 'Source';

int _sourceOrder(String a, String b) {
  int i(String s) => MediaSource.values.indexWhere((m) => m.label == s);
  return i(a).compareTo(i(b));
}

/// A Source field for a tab whose items have [sources]. Only offered in the sheet when the tab's
/// things come from more than one place (or one is picked).
FilterField<T> sourceField<T>(Iterable<MediaSource> Function(T item) sources) => FilterField<T>(
      sourceFieldLabel,
      (item) => {for (final s in sources(item)) s.label},
      order: _sourceOrder,
      onlyWhenSeveral: true,
    );

/// Every source among [tracks] (an album's or a book's songs).
Set<MediaSource> sourcesOfTracks(Iterable<Track> tracks) => {for (final t in tracks) sourceOfTrack(t)};

/// Every source among [videos] (a collection's).
Set<MediaSource> sourcesOfVideos(Iterable<VideoItem> videos) => {for (final v in videos) sourceOfVideo(v)};
