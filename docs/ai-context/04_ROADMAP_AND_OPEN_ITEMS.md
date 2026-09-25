# Roadmap and open items

## The agreed plan: "HomeTunes Sound & Offline Plan"
The plan is published as an artifact (https://claude.ai/artifact/QsNhvBvSRx69PNvz3ULyjp), updated
25 Sep 2026 (version 5) with the user's answers and two new pieces of work. Agreed order:
**A settings tidy-up → B equaliser → C multi-album (and book) edit → D offline server songs.**

| Phase | Status |
|---|---|
| 0: engine check | Done. The arm64 `libmpv.so` has lavfi `equalizer` and `scaletempo2`, but no `superequalizer` or rubberband. The equaliser was confirmed running on the phone (logcat, 25 Sep). |
| 1: gapless + ReplayGain | Done, in `main` |
| 2: lyrics | Done, in `main` |
| Book sidecar files | Done, in `main` |
| A: settings tidy-up | **Done, merged (0.1.9+9).** The phone has build 8, which lacks only the greyed-out Audiobookshelf boxes |
| B: equaliser (was phase 3) | **Done, merged (0.1.10).** Confirmed on the phone in logcat |
| C: multi-album + multi-book edit | **Done, merged (0.1.11)** |
| Favourite albums & books | **Done, merged (0.1.12)** |
| Quick actions + Details page | **Done, merged (0.1.13)** |
| D: offline copies of server songs (was phase 4) | After the server review |
| E: audiobook server (Audiobookshelf) | New 25 Sep. Needs a plan. The order relative to C and D isn't decided |

### A: Settings tidy-up (asked for 25 Sep)
The user wants Settings cleaner and easy to find things in. It used to be one long ListView
(975 lines). It's now built on `settings-tidy`; see `03_…` → Settings.
- **Section list:** Library, Playback, **Sleep timer** (its own page, as the user asked), Audiobooks,
  Online lookups, Music server, Your edits (save edits into files), Backup & restore, About (new:
  version and data folder).
- **Layout:** two panes on wide windows (sections on the left, the open page on the right). On
  phones it's a list, and each section opens its own page.
- **Search box:** type a word, see the matching settings, and tap one to jump to it.
- **Servers (asked for 25 Sep):** "Music server" was renamed **Servers**. It has two groups:
  - **Music server:** the Subsonic connection as before.
  - **Audiobooks:**
    - a new **"Audiobooks from the music server"** switch (`LibraryModel.serverBooks`, default on).
      When it's off, server tracks classed as books are dropped in `_rebuild`, and server music is
      unaffected.
    - an "Audiobook server" block. At the user's request it shows greyed-out boxes (server type,
      address, username, password, Connect) under a "coming in a later update" notice. It's
      `_AudiobookServerPreview` in `server_settings.dart`, and phase E makes it work.
- **No behaviour changes.** Keep the user's placement rule: book settings go in Audiobooks,
  playback settings in Playback, online look-ups in Online lookups. The sleep timer is the
  exception and has its own page.

### B: Equaliser (decided 25 Sep)
- **Presets UI:** the user picks from presets, not raw sliders on the main view. Built-ins: Flat,
  Bass boost, Treble boost, Vocal, Rock, Pop, Classical, Spoken word, Headphones.
- **Editing a preset:** Edit opens ten bands (31 Hz–16 kHz, ±12 dB) plus an overall level.
- **Restore defaults** (the user asked for this): an edited built-in shows "edited".
  "Restore default" works per preset, and there's a "Restore all presets" option.
- **Your own presets:** users can add their own (+ New), rename and delete them. Built-ins can only
  be restored.
- **Audiobooks:** books switch automatically to their own preset (default Spoken word, and the user
  can choose another). A switch in **Settings → Audiobooks** turns this off.
- **Implementation (built):** see `03_…` → Equaliser. It uses mpv `af` = `format=format=floatp,lavfi=[equalizer…]`,
  leaves out bands at or above half the file's sample rate, and does the overall level by scaling
  the player volume.
- **Where it lives:** Settings → Playback and a Now Playing button. Presets go into backups. Add
  `SettingTarget`s and catalog entries for search.

### C: Multi-album and multi-book edit (asked for 25 Sep, own branch, a new phase after current work)
- **Selecting:**
  - Right-click an album (desktop) or long-press it (phone) → Select. Tapping other albums ticks
    them, and there's a Select all option.
  - Works on the Albums tab, artist pages and search.
  - Today `SelectionModel` holds only song ids and `AlbumCard` has no menu or long-press. It needs
    album selection.
- **Edit albums** appears in the selection bar. It opens one form covering album artist, artist,
  year, genre and cover.
- **Differing values:** when the selected albums differ, the field shows **`--:--`** and is left
  as it is unless changed. Each field has an undo button to go back to `--:--`. Only changed fields
  are saved, as TrackEdits on every track of those albums.
- **Album title is excluded**, because the same title would merge albums. The user was told this
  and didn't object.
- `edit_details.dart` already has a `_mixed` set and a "Mixed - leave blank…" hint for
  multi-song edit. Reuse it.
- **Decided (25 Sep):**
  - Song multi-edit switches from "Mixed" to `--:--` too.
  - The Books page gets the same select-and-edit: author, narrator, series, year, genre and cover.

### E: Audiobook server (asked for 25 Sep)
- **User's answer:** books should come from **both** the music server and, optionally, a separate
  audiobook server.
- **Server software the user runs or plans to run:** Navidrome, Audiobookshelf, and Jellyfin/Plex.
- **Plan needed:**
  - An Audiobookshelf client (API-token login, libraries, items, chapters, covers, streaming, and
    maybe syncing listening progress with ABS).
  - Where it sits in Settings › Servers (the "Audiobook server" tile is the placeholder).
  - How ABS books join `groupBooks`.
  - Jellyfin/Plex later.
- **Still open for D:** whether the Navidrome server can transcode.

### D: Offline server songs
- **Needs first:** the server review.
- **Downloading:** download a song, album, playlist or Liked Songs. A "Keep offline" option
  follows albums and playlists. The quality is either the original or a server-converted copy.
- **Downloads screen:** progress, pause/retry, space used, delete.
- **Playback:** a downloaded copy plays first. Offline mode happens automatically when the server
  can't be reached.
- **Phone:** Wi-Fi-only, a storage limit, and downloads that continue in the background.
- **Backups:** list what's kept offline, but not the files themselves.
- **Open questions (ask when we get there):** the quality choice, and whether to add crossfade
  (it would need two players).

## Working agreements added 25 Sep
- **Ask before every phone install.** The phone is normally plugged in, but may have been removed.
- **Server questions and "All files access" on Android:** ask when they're needed, not before.
- Flutter is back on the PC at `C:\Users\James.Miller\flutter`.
- **Editing code:**
  - This session edited code in a cloud clone and pushed the branch. The PC then pulled it to
    analyze, test and build.
  - Dependency changes (`flutter pub add`) were made and committed on the PC, because the cloud
    has no Flutter.

## Needs reviewing with the user (when needed)
- **Server review (partly answered 25 Sep):**
  - The user runs or plans Navidrome, Audiobookshelf, and Jellyfin/Plex.
  - How audiobooks on the server should work: `bookKey` for server files uses album + author.
  - Whether the server can transcode.
- **Android and sidecar files:** the media permission hides jpg/json/txt/pdf. Options are an
  opt-in "All files access" (MANAGE_EXTERNAL_STORAGE, fine for sideloading) or leaving it as is.

## Known issues / small things
- **Dune collection tags are poor.** Many books show as "The New Dune Chronicles", with series
  taken from folder names like "01 - Dune Saga". The data itself is at fault, and the user can fix
  it with Edit book. Smarter guessing from folders would be possible.
- **VS Code F5 debug run on Windows can close after the scan.** Release is fine. This is parked.
- **Some tags are rewritten by the library, not preserved:**
  - The patched ID3 writer rewrites `TLEN` from the parsed duration, which may be slightly off for
    short files.
  - The FLAC vendor string is emptied.
  - Neither matters for playback.
- **iOS:** there's no local folder access, only server streaming. The server password is stored
  in plain text in the settings file.

## Offered earlier, not done (only if the user wants)
- Delete old installers in `build\dist` (0.1.0/0.1.2/0.1.3).
- GitHub Releases + Obtainium, so the phone can update itself.
- A sleep-timer button in the Android notification.

## Source control
`main` holds everything (0.1.13+13). The work was built on stacked branches (`equaliser` →
`multi-edit` → `favourites` → `details-and-quick-edits`) and merged in one `--no-ff` merge of the
last one on 25 Sep. The branches were then deleted, so there are no other branches. Builds (`build\dist`) are not in git; they are rebuilt from source with
the commands in `02_…`. The repo copy of these notes (`docs/ai-context/`) is kept the same as the
project copy.
