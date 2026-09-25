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

  /// Audiobook details (kept by HomeTunes; music files have no place for them).
  final String? narrator;
  final String? series;
  final double? seriesIndex;

  /// Lyrics chosen or typed by the user (plain text or timed LRC). An empty
  /// string means "this song has no lyrics" (hides any the file has).
  final String? lyrics;

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
    this.narrator,
    this.series,
    this.seriesIndex,
    this.lyrics,
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
      art == null &&
      narrator == null &&
      series == null &&
      seriesIndex == null &&
      lyrics == null;

  TrackEdit withoutArt() => _copy(keepArt: false);

  /// The same edit without lyrics.
  TrackEdit withoutLyrics() => _copy(keepLyrics: false);

  /// The same edit with [lyrics] (null removes them).
  TrackEdit withLyrics(String? lyrics) => _copy(keepLyrics: false, lyrics: lyrics);

  TrackEdit _copy({bool keepArt = true, bool keepLyrics = true, String? lyrics}) => TrackEdit(
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: trackNumber,
        discNumber: discNumber,
        year: year,
        genre: genre,
        art: keepArt ? art : null,
        narrator: narrator,
        series: series,
        seriesIndex: seriesIndex,
        lyrics: keepLyrics ? this.lyrics : lyrics,
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
        narrator: other.narrator ?? narrator,
        series: other.series ?? series,
        seriesIndex: other.seriesIndex ?? seriesIndex,
        lyrics: other.lyrics ?? lyrics,
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
        narrator: narrator == original.narrator ? null : narrator,
        series: series == original.series ? null : series,
        seriesIndex: seriesIndex == original.seriesIndex ? null : seriesIndex,
        // The file's own lyrics aren't part of a Track, so these always stay.
        lyrics: lyrics,
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
        narrator: narrator ?? t.narrator,
        series: series ?? t.series,
        seriesIndex: seriesIndex ?? t.seriesIndex,
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
        if (narrator != null) 'narrator': narrator,
        if (series != null) 'series': series,
        if (seriesIndex != null) 'seriesIndex': seriesIndex,
        if (lyrics != null) 'lyrics': lyrics,
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
        narrator: j['narrator'] as String?,
        series: j['series'] as String?,
        seriesIndex: (j['seriesIndex'] as num?)?.toDouble(),
        lyrics: j['lyrics'] as String?,
      );
}
