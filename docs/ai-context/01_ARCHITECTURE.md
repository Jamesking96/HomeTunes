# HomeTunes architecture

About 40.3k lines of Dart in `lib/` (8 Oct 2026), plus two vendored packages in `packages/`. State is handled by
Provider `ChangeNotifier`s created in `main.dart`, and screens `watch`/`select`/`read` them.

## Stack
- **Flutter 3.47.5 / Dart 3.10.** `pubspec.yaml` sets `sdk >=3.10.0` and `flutter >=3.38.0`.
- **media_kit ^1.2.6** with **media_kit_libs_audio ^1.0.7** (the audio-only libmpv builds) handles
  playback on all platforms. The engine is libmpv with FFmpeg n6.0: mpv 0.36 on Windows
  (`libmpv-2.dll`), mpv 0.35.1 on Android (`libmpv.so`); see `THIRD_PARTY_NOTICES.md`. It is
  LGPL 3.0 or later, so its licence texts ship in `licenses/` (see `app_licences.dart`).
- **audio_metadata_reader 1.8.0**, a *vendored and patched* copy in
  `packages/audio_metadata_reader` (see below). It reads tags, embedded art, Nero `chpl` chapters
  and lyrics, and writes tags.
- **audio_service ^0.18.19** provides the Android notification, lock screen and headset support.
  **audio_service_win**, a *vendored and patched* copy in `packages/audio_service_win`, provides
  the Windows media keys and SMTC overlay.
- **flutter_secure_storage ^11.2.0** keeps the server password in the system's protected
  storage (Windows Credential Manager, Android Keystore; see `secret_store.dart`). On Windows it
  needs Visual Studio's "C++ ATL" component.
- **package_info_plus ^10.2.1** reads the app's own version (About page, update check).
- Other packages: file_picker ^13.1.0, permission_handler_android ^14.1.0 +
  permission_handler_platform_interface ^4.4.1 (Android only, to avoid the full plugin's
  Windows NuGet part), provider, path_provider, path, http, crypto. Dev: flutter_test,
  flutter_lints ^6.0.0. There is no url_launcher: web links open with `rundll32 url.dll,FileProtocolHandler`
  on Windows and the `openUrl` MethodChannel call on Android (see Android specifics); files and
  folders open with `explorer`.

## Layout
```
lib/main.dart            creates Storage + models, wires them together, MultiProvider, MaterialApp(Shell)
lib/models/              plain data: Track (+Chapter, Album, Artist), TrackEdit, Book (+BookChapter), Playlist, Lyrics, EqPreset
lib/services/            no Flutter UI: files, network, platform
lib/state/               ChangeNotifiers + pure helpers (library_index, book_index, play_queue, music_filters, playback_guard)
lib/ui/shell.dart        wide: sidebar + DesktopPlayerBar; phone: MiniPlayer + bottom nav; per-tab Navigators (nav.dart AppNav)
lib/ui/theme.dart        colour themes (AppColors), corner roundness (AppShape), buildTheme, time formatters
lib/ui/screens/          pages & dialogs
lib/ui/screens/settings/ Settings: hub (list + search, two panes when ≥760 px), one file per page, catalog, shared widgets,
                         theme_sharing, update_ui (Check for updates), whats_new_ui ("What's new")
lib/ui/widgets/          shared widgets
packages/                vendored plugins (see below)
test/                    unit/widget tests (+ test/fixtures: small tagged mp3 (v2.3 and v2.4)/flac/m4a made with ffmpeg+mutagen)
tool/                    probes, benches (tool/bench/), UI preview renders, build_release.ps1, publish_release.ps1,
                         engine_source.ps1 + attach_engine_source.ps1 (engine LGPL source), switch_branch.ps1, platform patcher (patch_platforms.dart)
installer/               hometunes.iss (the Windows installer)
licenses/                LGPL-3.0 and GPL-3.0 texts for the audio engine (bundled as assets)
docs/                    USER_GUIDE.md (user-facing), ai-context/ (these notes), images/
```

## Models
- **`Track`**. The id is `local:<absolute path>` or `server:<subsonic id>`. It holds tags, duration,
  path/remoteId, `art` (a path to a cached image, or a server coverArt id), `modifiedMs`,
  `chapters`, and the book fields `narrator/series/seriesIndex`. Newer fields: `description`,
  `companions` (paths of PDF/EPUB files beside the book), `hasBookInfo` (a metadata sidecar was found) and `sidecarStamp`
  (rescan invalidation). Every field is serialised in `toJson/fromJson`. **If you add a field,
  also add it to `copyWith` and to `TrackEdit.applyTo`, which builds a Track by hand.**
- **`TrackEdit`**. These are the user's edits, stored separately from the file (null means "use
  the file's value"). Fields: the song details, `art`, the book fields, **`lyrics`** (`""`
  means "hide lyrics") and `cleared` (details the user emptied on purpose, from
  `clearableFields`: shown blank even though the file has a value). `normalizedAgainst(original)` drops edits that equal the file. `lyrics`
  is always kept because file lyrics aren't in `Track`.
- **`Book`** (built by `groupBooks` in `state/book_index.dart`) has `parts` (ordered tracks),
  title/author/narrator/series/seriesIndex/year, `description` and `companions`. Chapters come
  from the in-file chapters, otherwise one per file.
- **`Lyrics`** / `LyricLine` (`models/lyrics.dart`): an LRC parser (multiple stamps,
  `[offset:]`, `<word>` tags stripped), plain text, and `lineAt(position)`.
- **`EqPreset`** (`models/eq_preset.dart`): the ten bands (31 Hz–16 kHz), a preset's gains plus
  overall level, `builtInEqPresets`, and `eqFilter(preset, sampleRate:)`, which builds the mpv `af` text.

## State (ChangeNotifiers)
- **`LibraryModel`** is the core. It owns the settings (`settings.json`; since refactor phase 3 they're in groups in `state/settings/`, `LibraryModel.settings`, with the old names passing through), the scanned library
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
  - Settings setters: `updatePlaybackSettings`, `updateListeningSettings`, `setOnline*`,
    `setServerEnabled`, `setServerBooks`, `setBookGenres`, `setTheme`/`setLook` (Appearance,
    plus `savedThemes`), `setFormatShown` (folder options).
  - The server password lives in `SecretStore`, not `settings.json` (an old plain-text one is
    moved over on load). Server covers for the media controls go through `ServerArtCache`.
    Paths from scans or backups are checked with `path_safety.dart` before they're acted on.
- **`PlayerModel`** wraps media_kit. It holds the play queue (`play_queue.dart`: shuffle, repeat,
  play next, reorder), **gapless** preloading, book mode (`playBook`, parts and chapters,
  `skipBy` across files, speed per book, saving the place) and the waiting music queue while a
  book plays (`resumeMusic`), and the volume (0–100). It implements `SleepTarget`. It uses
  `StallDetector` (`playback_guard.dart`) to restart playback that has quietly stopped, and
  writes to the Playback log (`playback_log.dart`).
- **`ListeningModel`** (`listening.json`) stores each book's place, finished state and speed.
- **`BookmarksModel`** (`bookmarks.json`).
- **`PlaylistsModel`** (`playlists.json`, includes Liked Songs and `favouriteAlbums` /
  `favouriteBooks`, both stored as song ids; see `03_…` → Favourites).
- **`EqualizerModel`** (`equalizer.json`): on/off, the music and audiobook presets, edits to
  built-ins and your own presets. `PlayerModel` listens and applies it (see `03_…` → Equaliser).
- **`LyricsModel`** (`lyrics.json` = lyrics found online, plus "nothing found" timestamps) decides
  where lyrics come from (see `03_…`).
- **`UpdateModel`** (`updates.json`, not in backups): Check for updates, the check each time
  the app opens (`checkAtStart`, every start since 0.1.51; it was daily), and "What's new" after an update (`justUpdated`, `lastRunVersion`). The work is in
  `services/update_checker.dart`.
- **`SleepTimer`**, **`AppNav`** (per-tab navigators, `openBook/openAlbum/openArtist`, `openSettings(page, setting:)`) and
  **`SelectionModel`** (select mode: one `SelectKind` at a time, songs, albums or books, plus the
  scope that "Select all" covers). Provider creates these three itself; the others are made in
  `main()` and passed in with `.value`.

Pure helpers (no Flutter): `library_index.dart` (albums, artists, search), `book_index.dart`
(`BookRules`, `groupBooks`, Books tab sorting and filters), `play_queue.dart`, `music_filters.dart`
(title search, filters and sorting for the Artists/Albums/Songs tabs) and `playback_guard.dart`
(`SystemPlayingState`: hides an unasked-for pause from Android's media session for a few seconds
so a locked phone keeps playing; `StallDetector`).

## Services
| File | Role |
|---|---|
| `storage.dart` | JSON files in `<app support>/hometunes/`. Serial per-file lock; writes go to `<name>.tmp` and are then renamed. A damaged file is recovered from the `.tmp` if possible, otherwise kept as `<name>.corrupt-<date>.json` (up to 3) and reported in `problems`. Failed saves are reported too. `art/` holds cached covers (`art/custom/` for the user's). |
| `local_scanner.dart` | Walks folders in an isolate, then reads tags in **parallel isolates** (batch 60, up to 6 workers). An unchanged file (same `modifiedMs` + `sidecarStamp`) is reused. Covers are saved by md5 through a temp file and a rename. Applies sidecars (`book_sidecar.dart`). |
| `book_sidecar.dart` | Finds and parses files next to audio: Libation/Audible `.metadata.json`, Audiobookshelf `metadata.json`, images, description txt, PDFs. Also `htmlToText`. |
| `tag_writer.dart` | Writes edits into MP3/FLAC/M4A/WAV in an isolate, with an optional backup copy. It writes a working copy beside the file, re-reads and checks it, and only then replaces the original. Paths are checked with `path_safety.dart`. `TagSupport` says which fields each format holds; anything left over stays as an edit. |
| `subsonic_client.dart` | Token auth, `getAlbumList2`/`getAlbum` sync, stream/cover URLs, `fetchLyrics` (OpenSubsonic `getLyricsBySongId`, falls back to `getLyrics`). |
| `lrclib_client.dart` | LRCLIB `/api/get` and `/api/search`, ranking and matching (length within 3 s). The User-Agent names HomeTunes. |
| `local_lyrics.dart` | Tag lyrics and a sidecar `.lrc` file (any case of extension), read in an isolate. |
| `media_details.dart` | For the Details page: `inspectTrackNow` re-reads a file and works out where each shown detail came from (edit, book details file, tags, folder or file name, stand-in, server). Read-only. |
| `media_session.dart` | Links audio_service to the player (music: prev/next; books: rewind/fast-forward = skip). |
| `music_permission.dart` | Android READ_MEDIA_AUDIO (SDK ≥33) or storage permission, using the `sdkInt` MethodChannel. |
| `cover_search.dart`, `music_info.dart` | MusicBrainz / Cover Art Archive look-ups for songs. |
| `book_info.dart` | Open Library search and covers for books. |
| `app_backup.dart` | `.htbackup`, a gzip of JSON. `dataFiles` lists what's included, including `lyrics.json` and `equalizer.json`. A merge keeps both sides' favourites and custom equaliser presets. Paths are made portable (`@app/`). Merge or replace on restore. The password is optional. |
| `track_matching.dart` | Matches moved files to their old ids. |
| `path_safety.dart` | `isUsableLocalFile`: a path is only acted on (open PDF, show in Explorer, read a cover into tags, write tags) when it's a real file inside a library folder or the art folder, with the expected extension. Guards against crafted backups (0.1.21). |
| `secret_store.dart` | The server password in protected storage (flutter_secure_storage), keyed by server address + user name; an in-memory store under `flutter test`. |
| `server_art_cache.dart` | Downloads server covers to `art/server/` so the media controls get a `file://` path, not a URL carrying the login token (0.1.21). Not backed up; cleared when the server is forgotten. |
| `playback_log.dart` | The Playback log: the last 400 lines of what the player did, kept in `playback-log.txt`, shown in Settings › About. Not backed up. |
| `update_checker.dart` | Reads GitHub's latest release. On an installed Windows copy it downloads `HomeTunes-Setup-<v>.exe`, checks it against `SHA256SUMS` and runs it silently; elsewhere it opens the release page. |
| `app_licences.dart` | `registerAppLicences()` (called in `main`) adds the libmpv/FFmpeg notice and the bundled LGPL/GPL texts to Flutter's licence page (0.1.31). |

## Data files (app support dir `…/hometunes/`)
`settings.json`, `library.json`, `edits.json`, `playlists.json`, `listening.json`,
`bookmarks.json`, `lyrics.json`, `equalizer.json`, `videos.json` (0.1.40), `history.json`
(0.1.45, recently played music) and `servers.json` (0.1.46, the servers other than the main music
server, without passwords) (these eleven are `AppBackup.dataFiles`, the ones backups carry), plus `updates.json` and `playback-log.txt` (this device only, not backed up),
`art/` (+`art/custom/`, always backed up; `art/server/`, never), `backups/` (tag-write backups),
`before-restore.htbackup`. The server password is not in any of these (see `secret_store.dart`).

## Vendored packages (keep their HOMETUNES_CHANGES.md up to date)
- **`packages/audio_service_win`** (v0.0.3, `0.0.3+hometunes.1`). Patches are in
  `windows/audio_service_win_plugin.cpp`:
  - SMTC CommandManager disabled.
  - SMTC set up at start.
  - Next/prev always enabled.
  - Media-key presses are queued and run on Flutter's platform thread (0.1.17).
  - Covers are applied on the platform thread and only for the latest song (`coverGeneration`);
    `+` in cover paths is kept and `file://server/share` paths work (0.1.17).
  - The thumbnail error no longer prints the cover address (0.1.21).
  - `setQueue` (in the Dart side) is a silent no-op.
- **`packages/audio_metadata_reader`** (1.8.0). Its writers used to drop every tag they don't
  model. Patches, each marked `HomeTunes:`:
  - The ID3 writer carries over unmanaged v2.3/v2.4 frames (TXXX/ReplayGain, COMM, chapters…)
    and writes USLT.
  - The FLAC writer carries over unmanaged comments and writes DISCNUMBER and LYRICS.
  - The MP4 writer carries over ilst items it didn't write.
  - The USLT reader no longer drops a character when the frame has a description.
  - `buffer.dart`: `read(size)` throws instead of allocating when a block claims more than 1 MB
    past the end of the file, so a crafted file can't use up the memory during a scan (0.1.21).
  - Tested in `test/lyrics_test.dart` ("Saving edits into files keeps what HomeTunes doesn't
    change") and cross-checked with mutagen.
  - Analyzer excludes `packages/**`.

## Android specifics
- `MainActivity.kt` extends `AudioServiceActivity` and has the `hometunes/app` MethodChannel:
  `moveToBackground` (Back on Home keeps the music playing), `sdkInt` (which permission to ask
  for) and `openUrl` (0.1.23, used by the update check to open the release page; https only).
  `tool/patch_platforms.dart` only rewrites `MainActivity.kt` when it lacks `sdkInt`, and its
  template has no `openUrl`, so if the Android folder is ever regenerated, add `openUrl` back.
- The manifest has INTERNET, READ_MEDIA_AUDIO, READ_EXTERNAL_STORAGE (SDK ≤32), WAKE_LOCK and the
  foreground-service permissions, the audio_service service and media-button receiver,
  `usesCleartextTraffic` (home servers on plain http) and `requestLegacyExternalStorage`.
- `allowBackup="false"` plus `res/xml/data_extraction_rules.xml` (0.1.21): nothing goes to
  Google's cloud backup or to a new phone during setup. Moving phones uses a `.htbackup`.
- `res/raw/keep.xml` keeps the `audio_service_*` drawables. Without it, R8 strips them, the lock
  screen is empty and playback stops. `tool/patch_platforms.dart` recreates it along with the
  permissions, the backup rules and `compileSdk = 37`.
- With READ_MEDIA_AUDIO the app **can't see non-audio files** (jpg/json/txt/pdf) in shared
  storage. That's why book sidecars don't apply on the phone.
