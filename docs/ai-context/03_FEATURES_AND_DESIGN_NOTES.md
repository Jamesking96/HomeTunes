# Features and design notes

What's built, and the reasons behind choices that aren't obvious. Read the relevant section
before changing that area.

## Music library
- **Scanning.** The user picks folders; nothing else scans them. The scan is incremental: an
  unchanged file is reused, judged by `modifiedMs` and `sidecarStamp`. Isolate workers run in
  parallel. The whole app is rebuilt only a few times per scan. Rebuilding per batch was what made
  scans of thousands of files slow; now the first scan of 2,018 files takes about 0.9 s.
- **Grouping.** Albums group by `albumArtist + album`, and artists by album artist. Searching
  covers songs, albums, artists, books and book chapters.
- **Edits.** The user can edit a song, a whole album, or a multi-selection. Covers can be picked
  from a file or found online (MusicBrainz / Cover Art Archive), and so can details. Edits are
  stored in `edits.json`; the files are untouched until **Settings → Your edits → Save edits into music files**
  (with an optional backup copy). Tags the app doesn't edit are kept, thanks to the patched writer.
- **Missing songs.** Songs whose files disappear are kept if they have edits or are in playlists or
  Liked Songs. If a file moves, it's matched to its old id. Settings can forget missing songs.
- **Song lengths.** When a file has no length in its tags, the real length is learned the first
  time it plays.
- **Backups.** A `.htbackup` file can be restored by merging or replacing. The server password is
  included only if the user ticks it.
- **Server.** Subsonic/OpenSubsonic streaming, with cover art from the server. Server audiobooks
  are assumed to work but still **need a review** (see `04_…`).

## Player
- media_kit, one `Player`. The play queue and its rules (shuffle, repeat, play next, reorder) live
  in `PlayQueue`, not in the engine.
- **Gapless (phase 1).** The engine only ever holds `[now, next]` (`_engineIds`):
  - When the engine moves to entry 1, `_onEngineAdvanced` moves the queue forward, removes entry 0
    and preloads the next song.
  - Any queue change (shuffle, repeat, play next, add, remove, move) calls `_syncLoadedAhead`.
  - The engine fires `completed` just before each advance, so `completed` is **ignored while a
    song is preloaded**.
  - **Repeat-one** uses `PlaylistMode.single` with nothing preloaded, because preloading the same
    song stalled.
  - `_engineEdits` guards against reacting to our own playlist edits.
  - The mpv properties `gapless-audio`, `prefetch-playlist` and `replaygain` are set through
    `NativePlayer.setProperty` and only reapplied when they change.
  - Settings → Playback: gapless on/off, ReplayGain off/track/album.
- The mouse wheel over the volume control changes the volume.
- **Media controls.** On Android: notification, lock screen and headset buttons. On Windows: media
  keys and the overlay. For books, rewind and fast-forward do the skip amounts. Back on the
  Android Home screen keeps playing.

## Audiobooks (Books tab)
- **Which files are books**, first rule that applies wins:
  1. the user's "Move to Books/Music" override
  2. a metadata sidecar was found (`hasBookInfo`)
  3. the genre is in the user's book genres (default Audiobook / Audio Book / Audiobooks / Spoken Word)
  4. the file is `.m4b`
  5. a folder in the path is named like "audio books"
  6. the file is inside one of the user's audiobook folders
- **Grouping.** Each `.m4b` is its own book. Other files group by folder + album, and server files
  by album + author.
  - The series and number are guessed from folder names ("Book 01 - …"), and the narrator from
    "Read by …".
  - User edits and sidecar details beat these guesses: `buildBook` treats `Track.narrator/series`
    as authoritative.
- **Book mode** in the player:
  - Resume where you left off, with an optional short rewind when resuming.
  - Skip back 15 s and forward 30 s by default (both adjustable), across file boundaries.
  - Chapters, with previous/next chapter.
  - Speed from 0.75× to 2.5×, remembered per book.
  - Music queued while a book plays waits, and "Back to music" resumes it.
- **Sleep timer.**
  - A moon button beside play/pause, which can be hidden: one tap turns it on, another turns it
    off.
  - Books and music each have their own length in minutes, or "end of chapter" / "end of song".
  - The volume fades out, then playback pauses and the book's place is saved.
- **Bookmarks** with notes.
- **Book editing** changes title, author, narrator, series and number, year, genre and cover, for
  all of a book's files at once. Online look-ups use Open Library.
- The Books page can **sort and filter** by title, author, narrator, series (in series order),
  recently listened or recently added. Covers can be square or tall (a setting).
- A book is **in progress** once there's a saved place in it and it isn't finished.
- Settings live in **Settings → Audiobooks**. This is the user's rule for everything book-related,
  except the sleep timer, which the user wanted in its own **Settings → Sleep timer** page (music and books).

## Book sidecar files (`book-extras` branch)
- **Metadata sidecars.** `<name>.metadata.json` (Libation / audible-cli, Audible's schema) or an
  Audiobookshelf `metadata.json`.
  - These override the tags for title/album, author, narrators, series and number, year, genre
    (when there's none) and description.
  - The author list leaves out roles such as "X - translator".
  - **Chapters.** Libation M4Bs keep chapters in a QuickTime text track, which the reader can't see,
    so the JSON `ChapterInfo` provides them. Nested chapters are named "Heading: Part I", and
    headings under 10 s are dropped.
  - `chaptersFor(fileLength)` shifts the chapters by `brandIntroDurationMs` when the file length
    matches runtime − intro − outro (Libation can cut Audible's branding). It returns nothing when
    the length is more than 60 s off (a different edition).
- **Cover.** Chosen in this order:
  1. `<name>.jpg/png/webp`, which beats the embedded art
  2. then the embedded art
  3. then `cover|folder|front|album|poster.*`, then `<folder name>.*`, then the only picture in the
     folder
- **Description.** `<name>.txt`, `desc|description|summary|info|readme|about.txt`, or one of those
  in a parent collection folder that has no audio of its own.
- **Companions.** PDFs/EPUBs in the folder, but only those named after the book when several books
  share a folder. On desktop, the book page shows "Open the book's PDF".
- On Android these files are invisible (media permission), so nothing changes there.
- `sidecarStamp` hashes the sidecar names and modification times, so adding a file triggers a
  re-read. The first scan after upgrading re-reads everything once.

## Lyrics (`lyrics` branch)
- **Where they come from** (`LyricsModel`, first match wins):
  1. the user's lyrics (a TrackEdit; `""` = hidden)
  2. the file itself: the tags, or a `.lrc` file with the same name; timed beats plain
  3. lyrics found online before (`lyrics.json`, so they work offline)
  4. the server
  5. LRCLIB, if **Settings → Online lookups → Find lyrics online** is on
- A "nothing found" result is remembered for 14 days. Books don't auto-search.
- **Find lyrics on LRCLIB…** (in any song's ⋮ menu and in the lyrics view) lists the matches with
  a length check and a timed/plain label. The user previews one, and **Use these lyrics** saves it
  as their own lyrics.
- **Edit lyrics** lets the user paste or type plain or LRC text. Clearing it removes their
  lyrics. Hide and "Look again" are also available.
- **UI:**
  - A lyrics button in Now Playing: beside the cover on windows ≥900 px wide, in place of it on
    phones. The choice is remembered for the session.
  - The desktop player bar has a lyrics button.
  - Timed lines highlight and auto-scroll; auto-scroll pauses for 4 s after the user scrolls.
    Tapping a line seeks there.
- Lyrics can be written into MP3 (USLT), FLAC (LYRICS) and M4A (©lyr), but not WAV.

## Settings (`settings-tidy` branch, 0.1.9)
- **Pages:** Library, Playback, Sleep timer, Audiobooks, Online lookups, Servers, Your edits,
  Backup & restore and About, in that order (`SettingsPage` in `settings_catalog.dart`).
- **Layout:**
  - Wide (≥760 px of content): the list sits on the left and the open page on the right. Pages are
    capped at 820 px wide.
  - Phone: a list, and each page pushes on the Settings tab's navigator.
- **Search:** matches every typed word against the title, the page name and the extra words in
  `settingsCatalog`. Tapping a result opens the page, scrolls to the setting and briefly lights it up
  (`SettingTarget` + `SettingsHighlight`).
  - **When you add a setting, add a `SettingTarget(id)` and a catalog entry.**
    `test/settings_test.dart` checks that every catalog id is on its page.
  - Settings shown only sometimes (server password, include server music, missing songs) aren't in
    the catalog.
- **Links from other screens:** Home "Add music" and Books "Add audiobooks" use
  `AppNav.openSettings(...)` to go straight to the right page.
- **Servers:** the music server, then an Audiobooks group. That group has the "Audiobooks from the
  music server" switch (`serverBooks`) and a placeholder for a separate audiobook server (phase E).
- **About** shows the version (package_info_plus) and the data folder, with "Open folder" on Windows.

## Equaliser (`equaliser` branch, 0.1.10)
- **Where:** `EqualizerModel` (`equalizer.json`, included in backups) and `models/eq_preset.dart`.
  The screen is `ui/screens/equalizer_screen.dart`, opened from Settings › Playback, from Now
  Playing, and from the icon on the Settings › Audiobooks switch.
- **Presets:**
  - Built-ins: Flat, Bass boost, Treble boost, Vocal, Rock, Pop, Classical, Spoken word and
    Headphones. Each one that boosts also turns the overall level down.
  - Editing a built-in stores an override. It shows "· edited", and "Restore default" or "Restore
    all presets" removes the override. Moving the sliders back to the original counts as not edited.
  - Your own presets ("New", copied from the current one) can be renamed and deleted. Deleting one
    in use falls back to Flat or Spoken word.
- **Music vs audiobooks:**
  - `musicPresetId` and `bookPresetId` hold the two choices. `separateBooks` is on by default and is
    the switch in Settings › Audiobooks. When it's off, books use the music preset.
  - Choosing a preset switches the equaliser on. It starts off.
- **How it's heard (`PlayerModel._applyEqualizer`):**
  - It runs when the equaliser settings change, when switching between music and a book
    (`_setBook`), and when the file's sample rate changes (`stream.audioParams`).
  - Calls are coalesced, so dragging a slider doesn't pile up engine calls.
  - The filter is `format=format=floatp,lavfi=[equalizer=f=…:t=o:w=1:g=…, …]`, with one octave-wide
    band per non-zero slider.
- **Why it's built this way (found with `tool/bench/engine_test.dart` on 25 Sep):**
  - **media_kit's FFmpeg has no `aresample`.** On its own, the lavfi graph fails ("'aresample'
    filter not present, cannot convert formats") for any input that isn't planar, and mpv silently
    disables the filter. mpv's own `format=format=floatp` converter goes first to avoid that.
  - **The engine rejects the whole graph if a band is at or above Nyquist** (e.g. 16 kHz on 22 kHz
    audiobooks). `eqFilter(sampleRate:)` leaves those bands out. Before the first file's rate is
    known, all bands are sent; if that fails, the rate event re-sends without them.
  - **Just setting `af` and reading it back proves nothing.** mpv accepts the text and fails later.
    The bench plays a tone at 44.1 and 22.05 kHz at 1.5× and checks the log for filter errors.
  - **The overall level isn't a lavfi `volume` filter** (not certain to be in the Android build).
    The player sends `volume × 10^(level/20)` to the engine and keeps `PlayerModel.volume` as the
    user's own setting. The engine volume stream is no longer copied back.
- **"Isn't available on this device":** if `setProperty('af')` throws, `EqualizerModel.unavailable`
  is set and the screen says so. A runtime graph failure (as above) wouldn't be caught this way,
  which is why the bench matters.
- **Android:** the arm64 `libmpv.so` includes `equalizer` and `scaletempo2`. The equaliser must be
  heard on the phone before merging. Check it with
  `adb logcat | Select-String "HomeTunes: equaliser|lavfi|Disabling filter"`.

## Android fixes worth remembering
- **Lock screen empty and playback stopping.** The cause was "You must specify an icon resource id
  to build a CustomAction". It's fixed by `res/raw/keep.xml`.
- **Scanning found nothing on Android 13+.** It must request READ_MEDIA_AUDIO alone. Asking for
  storage as well gave a false "granted". The app shows a banner when access is missing, and never
  scans without access, because that would wipe the library.
