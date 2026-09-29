# HomeTunes

> **Just want to use it?** Download the app for your phone or PC from the
> [Releases page](https://github.com/Jamesking96/HomeTunes/releases/latest) and follow the
> **[download and user guide](docs/USER_GUIDE.md)**. The rest of this page is for developers.

A Spotify-style music player for **your own music files**. Point it at a folder and it builds a
library of artists, albums and songs from the tags in your files. Optionally, connect a
**Subsonic-compatible server** (Navidrome, Airsonic-Advanced, Gonic, Ampache…) to stream music you
keep on another machine, mixed in with your local library.

One Flutter codebase runs on **Windows, macOS, Linux and Android** (iOS builds too, see limits below).

## Features

- **Library** – scans MP3, FLAC, M4A/AAC, OGG, Opus and WAV; reads title/artist/album/album-artist/
  track/disc/year tags and embedded cover art (falls back to `cover.jpg`/`folder.jpg`, then to file
  and folder names). Rescans only re-read files that changed.
  `dart run tool/probe_library.dart <folder>` previews how a folder will be grouped.
- **Folders & scanning** (Settings) – music and audiobook folders in one place. Each folder has an
  options button (⋮) to **rescan just that folder** and a **File types** list: untick a format
  (e.g. WAV) and that folder's files of that type are left out of the library until ticked again.
- **Browse** – Home (quick tiles, recently added, artists), Library tabs for Playlists, Artists,
  Albums and Songs, album pages with multi-disc headings. On an artist page, clicking an album
  opens its songs right underneath the row it's in (with Play, Shuffle and Open album page);
  right-click → **Open album page** goes straight to the full page. Album covers show a play
  button when you hover over them.
- **Search** – instant, across songs, artists, albums, audiobooks and chapters; every word must match.
- **Playback** – queue, play next, add to queue, shuffle, repeat off/all/one, seek, full-screen
  Now Playing. The queue opens as a drawer from the side (drag to reorder, swipe to remove).
- **Volume everywhere** – the volume slider is in the player bar, Now Playing (lyrics view too)
  and, on the mini player, behind a speaker button. Clicking the speaker icon anywhere mutes, and
  clicking again brings back the previous volume.
- **Themes and appearance** (Settings › Appearance) – the Default look plus two ready-made dark
  themes (Midnight and Forest), **Your own** (pick an accent and background colour, with "Reset to
  default colours"), and **advanced themes**: every colour (background, panels, text, faded text,
  slider track, play button…) editable, dark or light, saved by name, edited and deleted later.
  The editor warns about hard-to-read combinations. Text size and corner roundness are adjustable
  too. Themes are kept in backups.
- **Updates** (Settings › About) – "Check for updates" looks at the latest GitHub release. On
  Windows the installer is downloaded, its checksum verified, installed quietly and HomeTunes
  reopens; the portable zip and Android open the download page instead. An optional quiet check
  at start-up (at most once a day) shows a banner when a new version is out. The first start
  after an update shows **What's new**: the "What's new in x" notes from every release page
  since the version you had (also in Settings › About).
- **Playlists** – create, rename, delete, reorder, add whole albums; plus **Liked Songs**.
- **Server streaming** – Subsonic API with token auth; server songs show a small cloud icon and can
  be switched off in Settings at any time.
- **Responsive** – sidebar + bottom player bar on desktop, mini player + bottom tabs on phones.
- **Edit song details** – title, artist, album, album artist, track/disc number, year, genre and
  cover image, for one song (⋮ → Edit details), a whole album (✎ on the album page), or several
  songs at once (long-press or ⋮ → Select, then ✎). Edits are stored by HomeTunes in `edits.json`;
  your music files are never modified, and "Reset to file details" undoes them. Changing a song's
  album-wide details (album, album artist, year, genre, cover) offers to update the rest of its
  album too, and editing an album offers to pull in songs with the same album title that show up
  as a separate album (e.g. "feat." songs with a different album artist).
- **Edit several albums or books at once** – right-click an album or book tile (press and hold on a
  phone) → Select, tick more or "Select all", then **Edit albums** / **Edit books** in the bar.
  Details that differ show `--:--` and are left alone unless you type something. Album and book
  titles can't be changed this way, since giving several the same title would merge them.
- **Favourite albums and audiobooks** – the heart on an album or book page, in a tile's menu, or in
  the selection bar. Favourites show a small heart on the cover, and Library › Albums and the Books
  tab have a Favourites filter. They're kept in backups.
- **Quick actions and Details** – right-clicking an album, book or song opens a menu with Edit
  details, Choose cover, Find cover online, Use the files' own cover, favourites and **Details…**.
  The Details page shows where something comes from: its folder and files, why it's in Books or
  Music, where each detail came from (tags, a book details file, the folder name, your edit…) and
  what the file itself says.
- **Save edits into files** (Settings) – writes your HomeTunes edits into the MP3/FLAC/M4A/WAV files
  themselves, backing each file up first by default. Fields a format can't hold (e.g. album artist
  in M4A, covers in WAV) stay as HomeTunes edits; OGG/Opus and server songs can't be written.
- **Find covers online** – for songs/albums with an artist or album name, search MusicBrainz / Cover
  Art Archive and pick a cover (from the edit dialog, or the prompt on album pages with no cover).
  Can be switched off in Settings.
- **Find song details online** – every field in the edit screen (title, artist, album, album artist,
  track/disc number, year, genre) has its own "find online" button, and album pages show a separate
  prompt for each missing detail (cover, artist, year, genre, track numbers). Details come from
  MusicBrainz; track numbers are matched to your songs by title. Own switch in Settings.
- **Songs with no length** – files that don't say how long they are show "–:––" until they're
  played once; the real length is then remembered. WAV lengths are read from the file header.
- **Songs that aren't on the device** – if a song's file is deleted, moved or on a drive that's
  unplugged, its edits and playlist / Liked Songs places are kept, and it's skipped when playing.
  When the file comes back – even in a different folder or on another device – the next scan
  picks it up again (matched by path, or by title/artist/album/track). Settings → Folders &
  scanning lists these songs and can forget them.
- **Backup & restore** (Settings) – exports everything HomeTunes keeps (folders, server, switches,
  themes, playlists, Liked Songs, edits, covers, library cache) to one `.htbackup` file, and
  imports it on the same or another PC/phone, replacing or merging. The server password is never
  included; you type it again after restoring. The data from just before a restore is kept as
  `before-restore.htbackup` in the app's data folder.
- **Audiobooks** – a separate Books tab. A file is a book when it's an `.m4b`, has an audiobook genre
  ("Audiobook", "Audio Book", "Spoken Word"… editable), sits in a folder named like "Audiobooks", or
  is in an audiobook folder (Settings → Audiobooks or Folders & scanning); "Move to Books" / "Move to Music" fixes
  any file by hand. Books are grouped per `.m4b` file or per folder + album; series, number and
  narrator are read from folder names like `Harry Potter Audio Books 1-7; Read by Stephen Fry` /
  `Book 01 - …`. HomeTunes remembers your place in every book (resuming a few seconds back), and
  the music queue waits while a book plays. "Continue listening" is on Home.
  While a book plays: previous/next chapter, skip back 15 s / forward 30 s (across files, amounts
  adjustable), speed 0.75×–2.5× remembered per book, and a chapter list. The lock screen,
  notification, headset buttons, keyboard media keys and the Windows overlay skip seconds too.
- **Book details and bookmarks** – ✎ on a book's page edits its title, author, narrator, series and
  number, year, genre and cover (choose an image, or find one on Open Library), for every file of
  the book at once; title, author and year have "find online" buttons too. Bookmarks (with notes)
  are added from Now Playing and listed on the book's page. Books show up in search, and backups
  include bookmarks and your place in every book.
- **Files beside a book** – HomeTunes uses the extras that often come with audiobooks:
  - `<book>.metadata.json` from Libation / audible-cli (Audible's details) or an Audiobookshelf
    `metadata.json`. It gives the title, author (translators left out), narrators, series and
    number, year, genre and description, and chapters when the file has none of its own (as with
    Libation's M4B files, lined up even when Audible's intro was cut). A metadata file also marks
    MP3s as a book.
  - the cover: `<book>.jpg`, `cover.jpg` / `folder.jpg`, a picture named after the folder, or
    the only picture in the folder.
  - a description: `<book>.txt`, `desc.txt`, `description.txt`, `summary.txt`, `info.txt` or
    `readme.txt`, also one in a collection folder above the books.
  - PDFs that come with a book: an "Open the book's PDF" button on its page (Windows, Mac, Linux).
  Your own edits still win. `dart run tool/probe_book_extras.dart <folder>` shows what's picked up.
- **Sleep timer** – the moon button beside play/pause: one tap starts it, another stops it. Books
  and music have their own length (minutes, or end of chapter / end of song), and the volume
  fades out before it pauses. All of these are in Settings → Sleep timer, where the button can
  also be hidden.
- **Gapless playback** – the next song is loaded while the current one plays, so albums that run
  straight on (live albums, mixes) have no silence between tracks; audiobook files join up too.
  Repeat-one loops without a gap. Can be switched off in Settings → Playback.
- **Even out volume (ReplayGain)** – off, by song or by album, using the loudness info many files
  carry (Settings → Playback).
- **Equaliser** – presets (Flat, Bass boost, Treble boost, Vocal, Rock, Pop, Classical, Spoken
  word, Headphones), each editable with ten bands and an overall level, "Restore default", and
  your own presets. Audiobooks get their own preset (Spoken word unless you choose another).
  Open it from Now Playing or Settings → Playback.
- **Lyrics** – the lyrics button in Now Playing (beside the cover on wide windows, in place of it
  on phones). Timed lyrics follow the song, and tapping a line jumps there. They come from the file's
  tags, a `.lrc` file with the same name, your server, or LRCLIB (lrclib.net, switch in Settings →
  Online lookups; only title, artist, album and length are sent, and what's found is saved).
  **Find lyrics on LRCLIB…** in any song's ⋮ menu shows the matches so you can check one before
  using it, even if the song already has lyrics. You can also edit or paste lyrics. They're kept as
  HomeTunes edits and can be saved into MP3, FLAC and M4A files.
  `dart run tool/probe_lyrics.dart "Title" "Artist" [seconds]` checks the LRCLIB look-up.
- **System media controls** – Android: media notification, lock screen, Bluetooth/headset buttons,
  and background playback that Android won't kill. Windows: keyboard media keys and the Windows
  media overlay. Back on the Android Home screen hides the app and keeps the music playing.

## Getting it running

### One-time setup of your PC

- **Flutter 3.47+** (Dart 3.10+): https://docs.flutter.dev/get-started/install — then run `flutter doctor`.
- **Windows builds**:
  - Turn on Developer Mode (`start ms-settings:developers`); Flutter plugins need it.
  - Visual Studio 2022 with the **Desktop development with C++** workload
    (MSVC v143 build tools, C++ CMake tools, Windows 10/11 SDK).
- **Android builds**:
  - Android Studio → SDK Manager:
    - *SDK Platforms*: **Android 37** (API 37).
    - *SDK Tools*: **Command-line Tools**, **Platform-Tools**, and **NDK (Side by side)**.
      Tick *Show Package Details* to pick the exact NDK version the build asks for.
  - On the phone: Developer options → **USB debugging** on, then allow the PC when prompted.
- **Linux builds**: `sudo apt install libmpv-dev mpv`.

### Running

From this folder:

```
flutter pub get
flutter run -d windows          # or: flutter devices, then flutter run -d <phone id>
```

Release builds: `flutter build windows` / `flutter build apk --release`
(APK ends up in `build/app/outputs/flutter-apk/`).

Checks: `flutter analyze` and `flutter test`.

### Sharing a Windows build

```
powershell -ExecutionPolicy Bypass -File tool\build_release.ps1
```

Creates in `build\dist\`:
- `HomeTunes-Setup-<version>.exe` – installer (per-user, no admin needed; Start-menu shortcut,
  optional desktop icon, uninstaller). Needs Inno Setup 6: `winget install JRSoftware.InnoSetup`.
- `HomeTunes-<version>-windows.zip` – portable copy: unzip and run `hometunes.exe`.

Both include the Visual C++ runtime DLLs, so they run on a clean Windows 10/11 (64-bit) PC.
The app isn't code-signed, so Windows SmartScreen shows "Windows protected your PC" the first
time: **More info → Run anyway**. Bump `version:` in `pubspec.yaml` for each release so the
installer upgrades cleanly. Always raise the build number after the `+` too (e.g. `0.1.5+4` →
`0.1.6+5`): Android refuses to install a build whose number is lower than the one on the phone (the installer's AppId in `installer/hometunes.iss` must never change).

Add `-Android` to also build a signed `HomeTunes-<version>-android.apk` (needs
`android/key.properties`; keep the same key, or phones can't update). `-SkipBuild` repackages an
existing build.

### Publishing a release

```
powershell -ExecutionPolicy Bypass -File tool\publish_release.ps1
```

Uploads the files in `build\dist\` for the current version to a GitHub release with a
`HomeTunes-<version>-SHA256SUMS.txt`. The in-app update check reads the latest release and
checks the installer against that file, so only publish finished builds. Re-running it
resumes an interrupted upload.

### Switching branches safely

`tool\switch_branch.ps1 <branch>` (`-New` to create one) refuses to switch while there are unsaved
changes or a `flutter run` is going, so work in progress is never carried onto another branch.

### Starting from the source zip instead of this repo

The zip has no platform folders. Run `setup.ps1` (Windows) or `setup.sh` once: it runs
`flutter create`, then `tool/patch_platforms.dart` adds the Android permissions, sets
`compileSdk = 37`, and adds the macOS/iOS entitlements.

### Troubleshooting

| Message | Fix |
|---|---|
| `No pubspec.yaml file found` | `cd` into this folder first. |
| `No Windows desktop project configured` | Platform folders are missing: run the setup script. |
| `symlink support` / Developer Mode | Turn on Developer Mode (see above). |
| NuGet / `Unable to load the service index` | Your PC's NuGet points at a feed you can't reach (e.g. a company feed off-VPN). Connect to that network or ask IT. |
| `Package ndk not found` / `sdkmanager ... non-zero exit value` | Install the requested NDK version in Android Studio's SDK Manager. |
| `Failed to find target ... android-37` | Install Android 37 under SDK Platforms and check `compileSdk = 37` in `android/app/build.gradle.kts`. |
| Java `source value 8 is obsolete` warnings | Harmless; they come from plugins. |
| `accessibility_bridge ... Failed to update ui::AXTree` | Harmless Flutter-on-Windows log message. |

## Using a server

Settings → *Servers*. Enter the address (e.g. `http://192.168.1.20:4533`), username and
password, then **Connect**. HomeTunes checks the login, then downloads the song list. Use
**Sync now** after adding music to the server.

If you don't have a server yet, [Navidrome](https://www.navidrome.org/) is a free, lightweight one
you can run on a spare PC, NAS or Raspberry Pi and point at the same music folder.

## Where things are stored

Library cache, playlists and settings are JSON files in the app's support folder
(on Windows, a `hometunes` folder under `%APPDATA%`). Your music files are only ever read,
never changed (unless you use *Save edits into files*, whose file backups go in the `backups`
folder there; those aren't part of an exported HomeTunes backup). Update-check settings are in
`updates.json` there and aren't backed up; downloaded installers go in a `HomeTunes-update`
folder in the system's temp folder.

The server password is not in those files: it's kept in the system's protected storage (Windows
Credential Manager, the Android Keystore, the macOS Keychain or the Linux keyring) and is never
put in a backup.

## Project layout

```
lib/
  main.dart                  start-up, providers
  models/                    Track, Album, Artist, Playlist, Book, Lyrics, EqPreset
  services/
    local_scanner.dart       folder walk + tag reading (background isolates)
    subsonic_client.dart     Subsonic REST client
    storage.dart             JSON file storage
    secret_store.dart        server password in the system's protected storage
    app_backup.dart          .htbackup export / import
    update_checker.dart      GitHub release check, verified installer download
  state/
    library_model.dart       library, folders, file-type filters, server, theme settings
    library_index.dart       grouping + search (pure Dart)
    play_queue.dart          queue / shuffle / repeat logic (pure Dart)
    player_model.dart        connects the queue to media_kit audio; volume and mute
    playlists_model.dart     playlists, Liked Songs, favourite albums and books
    equalizer_model.dart     equaliser presets and settings
    update_model.dart        update check state and the daily check
  ui/
    theme.dart               colour palettes, built-in themes, text size and corners
    screens/                 pages, incl. settings/ (one file per Settings tab)
    widgets/                 player bar, volume control, cards, dialogs
test/                        unit and widget tests (flutter test)
tool/
  build_release.ps1          Windows installer + zip (and -Android APK)
  publish_release.ps1        GitHub release upload with checksums
  switch_branch.ps1          safe branch switching
  patch_platforms.dart       adds Android/macOS/iOS permissions after `flutter create`
  probe_*.dart               command-line checks for scanning, books, lyrics, updates
installer/hometunes.iss      Inno Setup script
docs/USER_GUIDE.md           download and user guide
```

For a full tour of every file, see `docs/ai-context/05_CODE_GUIDE.md`.

## Known limits (good next steps)

- **Automatic updates** install themselves only with the Windows installer; the portable zip and
  Android open the download page. Builds aren't code-signed, so SmartScreen warns on first run.
- **Hot restart on Android** (debug only) disconnects the media notification until the app is
  fully restarted; this doesn't affect installed builds.
- **iOS**: iOS doesn't allow apps to read arbitrary folders; local playback there would need
  import through the Files app. Server streaming works.
- **Offline copies of server songs** (download for later) aren't implemented.
- Writing tags uses a patched copy of audio_metadata_reader (`packages/audio_metadata_reader`)
  that keeps lyrics, ReplayGain, comments and other tags it doesn't edit. Version 1.8.0 on its own
  drops them.
