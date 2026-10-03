// Home's "Jump back in" row (0.1.45): whatever you were last doing, newest first, mixed together:
// videos you're part-way through, audiobooks you're part-way through, and the albums,
// playlists, Liked Songs and artists you last played music from (PlayHistory).
//
// Each is a wide card (picture, what it is, title, a line of detail and a progress bar for
// videos and books) with a play button on the right: carry on watching or listening, or play
// that album / playlist / artist again. Tapping the card itself opens it the usual way (a video
// carries on playing; a book, album, playlist or artist opens its page).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/track.dart';
import '../../models/video_item.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/play_history.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'artwork.dart';

/// One card's worth: something to jump back into.
sealed class Jump {
  /// When it was last played (ms since 1970).
  int get atMs;
}

class VideoJump extends Jump {
  VideoJump(this.video, this.atMs, this.progress);
  final VideoItem video;
  @override
  final int atMs;
  final double progress;
}

class BookJump extends Jump {
  BookJump(this.book, this.atMs, this.progress);
  final Book book;
  @override
  final int atMs;
  final double progress;
}

class MusicJump extends Jump {
  MusicJump(this.item, this.tracks, {this.album});
  final PlayedItem item;
  final List<Track> tracks;
  final Album? album;
  @override
  int get atMs => item.atMs;
}

/// Everything to jump back into, newest first, at most [max]. Music whose album, playlist or
/// artist has gone (or has no songs now) is left out; the models are optional (tests).
List<Jump> jumpsFrom({
  required LibraryModel lib,
  ListeningModel? listening,
  PlaylistsModel? playlists,
  PlayHistory? history,
  VideoLibraryModel? videos,
  int max = 16,
}) {
  final out = <Jump>[];
  if (videos != null) {
    for (final v in videos.continueWatching) {
      final place = videos.placeOf(v.id);
      if (place != null) out.add(VideoJump(v, place.updatedMs, place.progress(v.duration)));
    }
  }
  if (listening != null) {
    for (final b in listening.inProgress(lib.books)) {
      out.add(BookJump(b, listening.progressFor(b)?.updatedMs ?? 0, listening.fractionDone(b)));
    }
  }
  for (final item in history?.items ?? const <PlayedItem>[]) {
    switch (item.kind) {
      case PlayedKind.album:
        final a = lib.albumByKey(item.key);
        if (a != null && a.tracks.isNotEmpty) out.add(MusicJump(item, a.tracks, album: a));
      case PlayedKind.playlist:
        final pl = playlists?.playlists.where((p) => p.name == item.key).firstOrNull;
        final tracks = pl == null ? const <Track>[] : [for (final id in pl.trackIds) ?lib.byId(id)];
        if (tracks.isNotEmpty) out.add(MusicJump(item, tracks));
      case PlayedKind.liked:
        final tracks = [for (final id in playlists?.liked ?? const <String>[]) ?lib.byId(id)];
        if (tracks.isNotEmpty) out.add(MusicJump(item, tracks));
      case PlayedKind.artist:
        final artist = lib.artists.where((a) => a.name == item.key).firstOrNull;
        if (artist != null && artist.tracks.isNotEmpty) out.add(MusicJump(item, artist.tracks));
    }
  }
  out.sort((a, b) => b.atMs.compareTo(a.atMs));
  return out.length > max ? out.sublist(0, max) : out;
}

/// The width of a card in the row.
const jumpCardWidth = 320.0;

/// The height of a card: 88 at the usual text size, taller with bigger text (Settings ›
/// Appearance › Text size, or the system's), so its three lines always fit.
double jumpCardHeightFor(BuildContext context) => 32 + MediaQuery.textScalerOf(context).scale(56);

/// A wide "Jump back in" card.
class JumpCard extends StatelessWidget {
  final Jump jump;
  const JumpCard({super.key, required this.jump});

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNav>();
    final accent = Theme.of(context).colorScheme.primary;
    final j = jump;
    late final String kind, title, detail, playTip;
    double? progress;
    late final Widget picture;
    late final VoidCallback open, play;
    switch (j) {
      case VideoJump(:final video):
        kind = 'Continue watching';
        title = video.title;
        detail = [video.collection, ?video.episodeLabel].join(' · ');
        progress = j.progress;
        final thumb = context.read<VideoLibraryModel>().thumbFile(video);
        picture = AspectRatio(
          aspectRatio: 16 / 9,
          child: thumb == null
              ? Container(
                  color: Colors.black,
                  child: Icon(Icons.movie_outlined, color: AppColors.textDim),
                )
              : Image.file(
                  File(thumb),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: Colors.black),
                ),
        );
        open = play = () => nav.openVideo(video);
        playTip = 'Carry on watching';
      case BookJump(:final book):
        kind = 'Continue listening';
        title = book.title;
        detail = '${book.author} · ${(j.progress * 100).round()}% done';
        progress = j.progress;
        picture = AspectRatio(aspectRatio: 1, child: ArtworkFill(track: book.artTrack, radius: 0));
        open = () => nav.openBook(book);
        play = () => context.read<PlayerModel>().playBook(book);
        playTip = 'Carry on listening';
      case MusicJump(:final item, :final tracks, :final album):
        final (k, label) = switch (item.kind) {
          PlayedKind.album => ('Album', 'Album · ${item.title}'),
          PlayedKind.playlist => ('Playlist', 'Playlist · ${item.title}'),
          PlayedKind.liked => ('Playlist', 'Liked Songs'),
          PlayedKind.artist => ('Artist', 'Artist · ${item.title}'),
        };
        kind = k;
        title = item.title;
        detail = switch (item.kind) {
          PlayedKind.album => album?.artist ?? '',
          PlayedKind.artist => '${tracks.length} songs',
          _ => '${tracks.length} songs',
        };
        picture = AspectRatio(
          aspectRatio: 1,
          child: item.kind == PlayedKind.liked
              ? Container(
                  color: accent.withValues(alpha: 0.25),
                  child: Icon(Icons.favorite, color: AppColors.current.onAccent),
                )
              : ArtworkFill(track: album?.artTrack ?? tracks.first, radius: 0),
        );
        open = switch (item.kind) {
          PlayedKind.album => () => nav.openAlbum(album!),
          PlayedKind.artist => () => nav.openArtist(item.key),
          PlayedKind.liked => nav.openLiked,
          PlayedKind.playlist => () {
            final pl = context.read<PlaylistsModel>().playlists.where((p) => p.name == item.key).firstOrNull;
            if (pl != null) nav.openPlaylist(pl);
          },
        };
        play = () => context.read<PlayerModel>().playTracks(tracks, label: label);
        playTip = 'Play ${item.title}';
    }

    return SizedBox(
      width: jumpCardWidth,
      height: jumpCardHeightFor(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: AppColors.surfaceHigh,
          borderRadius: AppShape.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Row(
              children: [
                picture,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textDim, fontSize: 12),
                        ),
                      if (progress != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: AppShape.circular(2),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: AppColors.surface,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: playTip,
                  icon: Icon(Icons.play_circle_fill, color: accent, size: 34),
                  onPressed: play,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
