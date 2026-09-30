// TrackEdit: the user's own changes to a song's details, kept apart from the music file.
// LibraryModel stores one TrackEdit per song id in edits.json and lays it over the scanned
// Track with applyTo() whenever the library is rebuilt. Keeping edits separate means a rescan
// never loses them, and the files stay untouched until the user chooses
// Settings -> Your edits -> Save edits into music files (services/tag_writer.dart).
// Null in any field means "no change, use the file's value".
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

  /// Details the user emptied on purpose: shown as blank even though the file has a value
  /// (e.g. a wrong year). Names from [clearableFields]. A field is never both set and cleared.
  ///
  /// HomeTunes (0.1.16): before this, an emptied box meant "no change", so a year or number in
  /// series couldn't be removed. Only fields that a Track can hold as "none" can be cleared.
  final Set<String> cleared;

  /// The details that can be cleared (the ones a Track can hold as null).
  static const clearableFields = {'trackNumber', 'discNumber', 'year', 'genre', 'narrator', 'series', 'seriesIndex'};

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
    this.cleared = const {},
  });

  /// An edit that changes nothing.
  static const empty = TrackEdit();

  /// True when nothing is changed, so the edit can be deleted.
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
      lyrics == null &&
      cleared.isEmpty;

  /// The same edit without the custom cover (goes back to the file's own art).
  TrackEdit withoutArt() => _copy(keepArt: false);

  /// The same edit without lyrics.
  TrackEdit withoutLyrics() => _copy(keepLyrics: false);

  /// The same edit with [lyrics] (null removes them).
  TrackEdit withLyrics(String? lyrics) => _copy(keepLyrics: false, lyrics: lyrics);

  // Shared helper for the three methods above: copies every field, optionally dropping
  // the cover and/or swapping the lyrics.
  TrackEdit _copy({bool keepArt = true, bool keepLyrics = true, String? lyrics}) => TrackEdit(
        cleared: cleared,
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

  /// Fields set in [other] win; fields it leaves null keep this edit's value, unless [other]
  /// clears them (see [cleared]). Used by LibraryModel.editTracks (e.g. album edits): only the
  /// fields the user touched are passed in [other].
  TrackEdit mergedWith(TrackEdit other) {
    // A field set or cleared by [other] replaces whatever this edit had for it.
    T? pick<T>(String name, T? mine, T? theirs) => theirs ?? (other.cleared.contains(name) ? null : mine);
    return TrackEdit(
      title: other.title ?? title,
      artist: other.artist ?? artist,
      album: other.album ?? album,
      albumArtist: other.albumArtist ?? albumArtist,
      trackNumber: pick('trackNumber', trackNumber, other.trackNumber),
      discNumber: pick('discNumber', discNumber, other.discNumber),
      year: pick('year', year, other.year),
      genre: pick('genre', genre, other.genre),
      art: other.art ?? art,
      narrator: pick('narrator', narrator, other.narrator),
      series: pick('series', series, other.series),
      seriesIndex: pick('seriesIndex', seriesIndex, other.seriesIndex),
      lyrics: other.lyrics ?? lyrics,
      cleared: {
        for (final f in cleared)
          if (other._valueOf(f) == null) f,
        ...other.cleared,
      },
    );
  }

  /// This edit's value for a clearable field (by name), or null.
  Object? _valueOf(String field) => switch (field) {
        'trackNumber' => trackNumber,
        'discNumber' => discNumber,
        'year' => year,
        'genre' => genre,
        'narrator' => narrator,
        'series' => series,
        'seriesIndex' => seriesIndex,
        _ => null,
      };

  /// This edit with the audiobook details (narrator, series, number in series, and whether
  /// they were cleared) taken from [other]. The song editor doesn't show those fields, so a
  /// save there keeps them instead of losing them (0.1.16).
  TrackEdit withBookDetailsFrom(TrackEdit? other) {
    const book = {'narrator', 'series', 'seriesIndex'};
    return TrackEdit(
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      genre: genre,
      art: art,
      narrator: other?.narrator,
      series: other?.series,
      seriesIndex: other?.seriesIndex,
      lyrics: lyrics,
      cleared: {
        for (final f in cleared)
          if (!book.contains(f)) f,
        for (final f in other?.cleared ?? const <String>{})
          if (book.contains(f)) f,
      },
    );
  }

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
        // Clearing something the file doesn't have anyway changes nothing.
        cleared: {
          for (final f in cleared)
            if (_trackValue(original, f) != null) f,
        },
      );

  /// A Track's value for a clearable field (by name).
  static Object? _trackValue(Track t, String field) => switch (field) {
        'trackNumber' => t.trackNumber,
        'discNumber' => t.discNumber,
        'year' => t.year,
        'genre' => t.genre,
        'narrator' => t.narrator,
        'series' => t.series,
        'seriesIndex' => t.seriesIndex,
        _ => null,
      };

  /// The song as the user wants to see it.
  /// Built field by field (not with copyWith) because copyWith only changes a few fields.
  /// Anything the user can't edit (id, path, length, chapters, sidecar info) is copied as is.
  Track applyTo(Track t) => Track(
        id: t.id,
        source: t.source,
        title: title ?? t.title,
        artist: artist ?? t.artist,
        album: album ?? t.album,
        albumArtist: albumArtist ?? t.albumArtist,
        trackNumber: cleared.contains('trackNumber') ? null : (trackNumber ?? t.trackNumber),
        discNumber: cleared.contains('discNumber') ? null : (discNumber ?? t.discNumber),
        year: cleared.contains('year') ? null : (year ?? t.year),
        genre: cleared.contains('genre') ? null : (genre ?? t.genre),
        duration: t.duration,
        path: t.path,
        remoteId: t.remoteId,
        art: art ?? t.art,
        modifiedMs: t.modifiedMs,
        chapters: t.chapters,
        narrator: cleared.contains('narrator') ? null : (narrator ?? t.narrator),
        series: cleared.contains('series') ? null : (series ?? t.series),
        seriesIndex: cleared.contains('seriesIndex') ? null : (seriesIndex ?? t.seriesIndex),
        description: t.description,
        companions: t.companions,
        hasBookInfo: t.hasBookInfo,
        sidecarStamp: t.sidecarStamp,
        video: t.video,
      );

  /// For edits.json. Only the changed fields are written.
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
        if (cleared.isNotEmpty) 'cleared': [...cleared]..sort(),
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
        cleared: {
          for (final f in (j['cleared'] as List? ?? const []))
            if (f is String && clearableFields.contains(f)) f,
        },
      );
}
