# HomeTunes

A Spotify-style music player for **your own music files**. Point it at a folder and it builds a
library of artists, albums and songs from the tags in your files. Optionally, connect a
**Subsonic-compatible server** (Navidrome, Airsonic-Advanced, Gonic, Ampache…) to stream music you
keep on another machine, mixed in with your local library.

One Flutter codebase runs on **Windows, macOS, Linux and Android** (iOS builds too, see limits below).

## Features

- **Library** – scans MP3, FLAC, M4A/AAC, OGG, Opus and WAV; reads title/artist/album/album-artist/
  track/disc/year tags and embedded cover art (falls back to `cover.jpg`/`folder.jpg`, then to file
  and folder names). Rescans only re-read files that changed.
- **Browse** – Home (quick tiles, recently added, artists), Library tabs for Playlists, Artists,
  Albums and Songs, album pages with multi-disc headings, artist pages.
- **Search** – instant, across songs, artists and albums; every word must match.
- **Playback** – queue, play next, add to queue, shuffle, repeat off/all/one, seek, volume,
  full-screen Now Playing, drag-to-reorder / swipe-to-remove queue.
- **Playlists** – create, rename, delete, reorder, add whole albums; plus **Liked Songs**.
- **Server streaming** – Subsonic API with token auth; server songs show a small cloud icon and can
  be switched off in Settings at any time.
- **Responsive** – sidebar + bottom player bar on desktop, mini player + bottom tabs on phones.

## Getting it running

1. Install Flutter (3.38 or newer): https://docs.flutter.dev/get-started/install
   For Android also install Android Studio (it brings the Android SDK).
2. In this folder run the one-time setup, which generates the platform folders and adds the
   permissions the app needs:
   - Windows: `./setup.ps1` (PowerShell)
   - macOS / Linux: `./setup.sh`
3. Run it:
   - `flutter run -d windows` (or `-d macos`, `-d linux`)
   - Android phone plugged in with USB debugging on: `flutter run -d android`
4. Build a release: `flutter build windows` / `flutter build apk --release`.

Linux also needs libmpv: `sudo apt install libmpv-dev mpv`.

Run the tests with `flutter test`.

## Using a server

Settings → *Music server*. Enter the address (e.g. `http://192.168.1.20:4533`), username and
password, then **Connect**. HomeTunes checks the login, then downloads the song list. Use
**Sync now** after adding music to the server.

If you don't have a server yet, [Navidrome](https://www.navidrome.org/) is a free, lightweight one
you can run on a spare PC, NAS or Raspberry Pi and point at the same music folder.

## Where things are stored

Library cache, playlists and settings are JSON files in the app's support folder
(on Windows, a `hometunes` folder under `%APPDATA%`). Your music files are only ever read,
never changed. The server password is stored in that settings file in plain text, so use an
account that only has access to music.

## Project layout

```
lib/
  main.dart                  start-up, providers
  models/                    Track, Album, Artist, Playlist
  services/
    local_scanner.dart       folder walk + tag reading (background isolates)
    subsonic_client.dart     Subsonic REST client
    storage.dart             JSON file storage
  state/
    library_model.dart       library, folders, server settings
    library_index.dart       grouping + search (pure Dart)
    play_queue.dart          queue / shuffle / repeat logic (pure Dart)
    player_model.dart        connects the queue to media_kit audio
    playlists_model.dart     playlists + Liked Songs
  ui/                        shell, screens, widgets, theme
test/                        queue, library, search and Subsonic tests
tool/patch_platforms.dart    adds Android/macOS/iOS permissions after `flutter create`
```

## Known limits (good next steps)

- **Android background / lock-screen controls**: music keeps playing while the app is in the
  background, but there is no media notification yet. Adding `audio_service` is the next step.
- **iOS**: iOS doesn't allow apps to read arbitrary folders; local playback there would need
  import through the Files app. Server streaming works.
- **Offline copies of server songs** (download for later) aren't implemented.
- No lyrics, equaliser or gapless playback yet.
