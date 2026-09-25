# HomeTunes architecture

About 14k lines of Dart in `lib/`, plus two vendored packages in `packages/`. State is handled by
Provider `ChangeNotifier`s created in `main.dart`, and screens `watch`/`select`/`read` them.

## Stack
- **Flutter 3.47.5 / Dart 3.10.** `pubspec.yaml` sets `sdk >=3.10`.
- **media_kit 1.2.6** (libmpv: mpv 0.36, ffmpeg 6.0) handles playback on all platforms.
- **audio_metadata_reader 1.8.0**, a *vendored and patched* copy in
  `packages/audio_metadata_reader` (see below). It reads tags, embedded art, Nero `chpl` chapters
  and lyrics, and writes tags.
- **audio_service 0.18.19** provides the Android notification, lock screen and headset support.
  **audio_service_win**, a *vendored and patched* copy in `packages/audio_service_win`, provides
  the Windows media keys and SMTC overlay.
- Other packages: file_picker, permission_handler_android (Android only, to avoid the Windows
  NuGet part), provider, path_provider, http, crypto.

## Layout
```
lib/main.dart            creates Storage + models, wires them together, MultiProvider, MaterialApp(Shell)
lib/models/              plain data: Track (+Chapter, Album, Artist), TrackEdit, Book (+BookChapter), Playlist, Lyrics
lib/services/            no Flutter UI: files, network, platform
lib/state/               ChangeNotifiers + pure helpers (library_index, book_index, play_queue)
lib/ui/shell.dart        wide: sidebar + DesktopPlayerBar; phone: MiniPlayer + bottom nav; per-tab Navigators (nav.dart AppNav)
lib/ui/screens/          pages & dialogs
lib/ui/widgets/          shared widgets
packages/                vendored plugins (see below)
test/                    unit/widget tests (+ test/fixtures: small tagged mp3/flac/m4a made with ffmpeg+mutagen)
tool/                    probes, benches, build script, platform patcher
```

## Models
- **`Track`**. The id is `local:<absolute path>` or `server:<subsonic id>`. It holds tags, duration,
  path/remoteId, `art` (a path to a cached image, or a server coverArt id), `modifiedMs`,
  `chapters`, and the book fields `narrator/series/seriesIndex`. Newer fields: `description`,
  `companions` (PDF paths), `hasBookInfo` (a metadata sidecar was found) and `sidecarStamp`
  (rescan invalidation). Every field is serialised in `toJson/fromJson`. **If you add a field,
  also add it to `copyWith` and to `TrackEdit.applyTo`, which builds a Track by hand.**
- **`TrackEdit`**. These are the user's edits, stored separately from the file (null means "use
  the file's value"). Fields: the song details, `art`, the book fields and **`lyrics`** (`""`
  means "hide lyrics"). `normalizedAgainst(original)` drops edits that equal the file. `lyrics`
  is always kept because file lyrics aren't in `Track`.
- **`Book`** (built by `groupBooks` in `state/book_index.dart`) has `parts` (ordered tracks),
  title/author/narrator/series/seriesIndex/year, `description` and `companions`. Chapters come
  from the in-file chapters, otherwise one per file.
- **`Lyrics`** / `LyricLine` (`models/lyrics.dart`): an LRC parser (multiple stamps,
  `[offset:]`, `<word>` tags stripped), plain text, and `lineAt(position)`.

## State (ChangeNotifiers)
- **`LibraryModel`** is the core. It owns the settings (`settings.json`), the scanned library
  (`library.json`: local, remote and missing lists), edits (`edits.json`), and the derived
  tracks/albums/artists/books.
  - `_rebuild()` applies edits, then decides music vs book (`BookRules.isBook`), then groups.
  - Scans and syncs run one after another (`_enqueue`). `statusText` is a separate `ValueNotifier`
    so scan progress doesn't redraw the whole app.
  - It keeps "missing" songs (files gone) that have edits or are referenced by playlists. It
    follows moved files via `track_matching.dart` and `onIdsRemapped`.
  - `setEdit` keeps existing lyrics. `resetEdits` keeps lyrics too.
  - Write-back into files: `writeEditsToFiles` uses `tag_writer.dart`.
  - Backup and restore: `app_backup.dart`.
  - Settings setters: `updatePlaybackSettings`, `updateListeningSettings`, `setOnline*`.
- **`PlayerModel`** wraps media_kit. It holds the play queue (`play_queue.dart`: shuffle, repeat,
  play next, reorder), **gapless** preloading, book mode (`playBook`, parts and chapters,
  `skipBy` across files, speed per book, saving the place) and the waiting music queue while a
  book plays (`resumeMusic`). It implements `SleepTarget`.
- **`ListeningModel`** (`listening.json`) stores each book's place, finished state and speed.
- **`BookmarksModel`** (`bookmarks.json`).
- **`PlaylistsModel`** (`playlists.json`, includes Liked Songs).
- **`LyricsModel`** (`lyrics.json` = lyrics found online, plus "nothing found" timestamps) decides
  where lyrics come from (see `03_…`).
- **`SleepTimer`**, **`AppNav`** (per-tab navigators, `openBook/openAlbum/openArtist`) and
  **`SelectionModel`** (multi-select).

## Services
| File | Role |
|---|---|
| `storage.dart` | JSON files in `<app support>/hometunes/`. Serial per-file lock; writes go to a temp file and are then renamed. `art/` holds cached covers (`art/custom/` for the user's). |
| `local_scanner.dart` | Walks folders in an isolate, then reads tags in **parallel isolates** (batch 60, up to 6 workers). An unchanged file (same `modifiedMs` + `sidecarStamp`) is reused. Covers are saved by md5 through a temp file and a rename. Applies sidecars (`book_sidecar.dart`). |
| `book_sidecar.dart` | Finds and parses files next to audio: Libation/Audible `.metadata.json`, Audiobookshelf `metadata.json`, images, description txt, PDFs. Also `htmlToText`. |
| `tag_writer.dart` | Writes edits into MP3/FLAC/M4A/WAV in an isolate, with an optional backup copy. After writing it re-reads the file to verify. `TagSupport` says which fields each format holds; anything left over stays as an edit. |
| `subsonic_client.dart` | Token auth, `getAlbumList2`/`getAlbum` sync, stream/cover URLs, `fetchLyrics` (OpenSubsonic `getLyricsBySongId`, falls back to `getLyrics`). |
| `lrclib_client.dart` | LRCLIB `/api/get` and `/api/search`, ranking and matching (length within 3 s). The User-Agent names HomeTunes. |
| `local_lyrics.dart` | Tag lyrics and a sidecar `.lrc` file (any case of extension), read in an isolate. |
| `media_session.dart` | Links audio_service to the player (music: prev/next; books: rewind/fast-forward = skip). |
| `music_permission.dart` | Android READ_MEDIA_AUDIO (SDK ≥33) or storage permission, using the `sdkInt` MethodChannel. |
| `cover_search.dart`, `music_info.dart` | MusicBrainz / Cover Art Archive look-ups for songs. |
| `book_info.dart` | Open Library search and covers for books. |
| `app_backup.dart` | `.htbackup`, a gzip of JSON. `dataFiles` lists what's included, including `lyrics.json`. Paths are made portable (`@app/`). Merge or replace on restore. The password is optional. |
| `track_matching.dart` | Matches moved files to their old ids. |

## Data files (app support dir `…/hometunes/`)
`settings.json`, `library.json`, `edits.json`, `playlists.json`, `listening.json`,
`bookmarks.json`, `lyrics.json`, `art/` (+`art/custom/`), `backups/` (tag-write backups),
`before-restore.htbackup`.

## Vendored packages (keep their HOMETUNES_CHANGES.md up to date)
- **`packages/audio_service_win`** (v0.0.3):
  - SMTC CommandManager disabled.
  - SMTC set up at start.
  - Next/prev always enabled.
  - `setQueue` is a silent no-op.
- **`packages/audio_metadata_reader`** (1.8.0). Its writers used to drop every tag they don't
  model. Patches, each marked `HomeTunes:`:
  - The ID3 writer carries over unmanaged v2.3/v2.4 frames (TXXX/ReplayGain, COMM, chapters…)
    and writes USLT.
  - The FLAC writer carries over unmanaged comments and writes DISCNUMBER and LYRICS.
  - The MP4 writer carries over ilst items it didn't write.
  - The USLT reader no longer drops a character when the frame has a description.
  - Tested in `test/lyrics_test.dart` and cross-checked with mutagen.
  - Analyzer excludes `packages/**`.

## Android specifics
- `MainActivity.kt` has the `hometunes/app` MethodChannel: `moveToBackground` (Back on Home
  keeps the music playing) and `sdkInt`.
- `res/raw/keep.xml` keeps the `audio_service_*` drawables. Without it, R8 strips them, the lock
  screen is empty and playback stops. `tool/patch_platforms.dart` recreates it along with the
  permissions and `compileSdk = 37`.
- With READ_MEDIA_AUDIO the app **can't see non-audio files** (jpg/json/txt/pdf) in shared
  storage. That's why book sidecars don't apply on the phone.
