import 'track.dart';

/// The user's changes to one song's details, stored by HomeTunes (the music
/// file itself is never modified). Every field is optional: null means
/// "use what the file says".
class TrackEdit {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? year;
  final String? genre;

  /// Path of a cover image chosen by the user (a copy kept in the app's data folder).
  final String? art;

  const TrackEdit({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.art,
  });

  static const empty = TrackEdit();

  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      albumArtist == null &&
      trackNumber == null &&
      discNumber == null &&
      year == null &&
      genre == null &&
      art == null;

  TrackEdit withoutArt() => TrackEdit(
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
        genre: genre,
      );

  /// Fields set in [other] win; fields it leaves null keep this edit's value.
  TrackEdit mergedWith(TrackEdit other) => TrackEdit(
        title: other.title ?? title,
        artist: other.artist ?? artist,
        album: other.album ?? album,
        albumArtist: other.albumArtist ?? albumArtist,
        trackNumber: other.trackNumber ?? trackNumber,
        discNumber: other.discNumber ?? discNumber,
        year: other.year ?? year,
        genre: other.genre ?? genre,
        art: other.art ?? art,
      );

  /// Drops fields that match the file's own values, so a song that's been
  /// edited back to how it was has no edit left over.
  TrackEdit normalizedAgainst(Track original) => TrackEdit(
        title: title == original.title ? null : title,
        artist: artist == original.artist ? null : artist,
        album: album == original.album ? null : album,
        albumArtist: albumArtist == original.albumArtist ? null : albumArtist,
        trackNumber: trackNumber == original.trackNumber ? null : trackNumber,
        discNumber: discNumber == original.discNumber ? null : discNumber,
        year: year == original.year ? null : year,
        genre: genre == original.genre ? null : genre,
        art: art == original.art ? null : art,
      );

  /// The song as the user wants to see it.
  Track applyTo(Track t) => Track(
        id: t.id,
        source: t.source,
        title: title ?? t.title,
        artist: artist ?? t.artist,
        album: album ?? t.album,
        albumArtist: albumArtist ?? t.albumArtist,
        trackNumber: trackNumber ?? t.trackNumber,
        discNumber: discNumber ?? t.discNumber,
        year: year ?? t.year,
        genre: genre ?? t.genre,
        duration: t.duration,
        path: t.path,
        remoteId: t.remoteId,
        art: art ?? t.art,
        modifiedMs: t.modifiedMs,
        chapters: t.chapters,
      );

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (discNumber != null) 'discNumber': discNumber,
        if (year != null) 'year': year,
        if (genre != null) 'genre': genre,
        if (art != null) 'art': art,
      };

  factory TrackEdit.fromJson(Map<String, dynamic> j) => TrackEdit(
        title: j['title'] as String?,
        artist: j['artist'] as String?,
        album: j['album'] as String?,
        albumArtist: j['albumArtist'] as String?,
        trackNumber: j['trackNumber'] as int?,
        discNumber: j['discNumber'] as int?,
        year: j['year'] as int?,
        genre: j['genre'] as String?,
        art: j['art'] as String?,
      );
}
