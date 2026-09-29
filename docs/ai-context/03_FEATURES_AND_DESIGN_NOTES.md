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
- **Library tabs (0.1.18).** Artists, Albums and Songs each have a filter-by-title box (every
  typed word must be in the title), All / Favourites chips (Liked for songs), a "Show only" sheet
  (artist, album, genre, decade) and a sort menu, like the Books tab. Choices last while the app
  is open but aren't saved; the Albums year sorts split the grid by decade.
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
- **Volume everywhere (0.1.22, asked for 29 Sep).** `VolumeControl` is in the desktop player bar
  (120 px), across Now Playing under the play buttons (`sliderWidth: null`, fills the row), and in
  the phone mini player as `VolumeButton`: a speaker icon whose `MenuAnchor` pop-up holds a 200 px
  slider (the user picked the pop-up over an always-visible row). Now Playing is pushed on the
  root navigator and covers the desktop bar, which is why it needed its own slider: it's there
  with the cover and with the lyrics. On Android this is HomeTunes' own level, on top of the
  phone's volume buttons.
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
- **Pages:** since 0.1.26 in A–Z order: About, Appearance, Audiobooks, Backup & restore, Folders &
  scanning (code name `library`), Online lookups, Playback, Servers, Sleep timer, Your edits
  (`SettingsPage` in `settings_catalog.dart`).
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
  Since 0.1.23 it also has **Check for updates** and **Check for updates automatically** (see
  below).

## Colour themes (`feature/themes`, 0.1.24, asked for 29 Sep)
- **The user's choices (29 Sep):** the original look stays as **Default**; two more dark themes,
  **Midnight** (navy, sky-blue accent) and **Forest** (dark green-grey, green accent); and **Your
  own** = a highlight + a background colour, with panels and grey text worked out from those.
  The choice goes into backups (settings.json: `theme`, `customAccent`, `customBackground` as
  `#RRGGBB`; a *merge* restore keeps this device's theme, like other settings).
- **Where:** a new **Settings › Appearance** page (`appearance_settings.dart`) with a preview card
  per theme and a colour picker (suggested swatches + Shade / Strength / Brightness sliders).
  Backgrounds are held at HSL lightness ≤ 0.2 and highlights 0.45–0.8, so white text stays
  readable (`AppPalette.keepDark` / `keepVisible`).
- **How it works:** `ui/theme.dart` has `AppPalette`, `builtInPalettes`, `paletteFor`, and
  `AppColors` is now **getters** reading `AppColors.current` (they used to be `static const`).
  HomeTunesApp (main.dart) wraps MaterialApp in a `Selector<LibraryModel, AppPalette>`, sets
  `AppColors.current`, builds `buildTheme(palette)` and `RedrawOnThemeChange` marks every element
  to build again after a change (widgets that read AppColors directly wouldn't notice otherwise).
- **Rule for new code:** never put `AppColors.x` in a `const`, a `static final` or a top-level
  `final`; read it in `build`. The compiler catches the `const` case. When the change was made,
  102 `const` keywords were removed by a script (`C:\Temp\ht\deconst.py`, not in git).
- **Tests:** `test/theme_test.dart`. Pictures of each theme without showing anything on screen:
  `flutter test tool/theme_preview_test.dart` writes PNGs to `C:\Temp\ht\preview`.
- **Don't take screenshots of the user's desktop or launch the app on their screen** to check the
  look: on 29 Sep that captured a game the user was playing. Use the off-screen preview instead.

## Folder options and mute (`feature/folder-options`, 0.1.27, asked for 29 Sep 19:33)
- **Folder options:** every music and audiobook folder row (Folders & scanning, and the shared
  audiobook list under Audiobooks) has a sliders button (`FolderOptionsButton`) that opens
  `showFolderOptions` (library_settings.dart):
  - **Rescan this folder** → `LibraryModel.scanFolder(folder)`: scans only that folder, replaces
    the songs inside it and keeps everything else, then reconciles/saves like a full scan. An
    unreachable folder keeps what it had and says so.
  - **File types**: an ExpansionTile (the "drop-down") listing every type found in that folder
    at the last scan (`formatsIn`, with file counts), each with a tick box. Unticking adds it to
    `hiddenFormats[folder]` (settings.json `hiddenFormats`, so in backups); `_rebuild` leaves
    those files out of `raw`, so they vanish at once without a rescan and come back when ticked.
    They stay in `_local`, which is how the list still knows about them. A file belongs to the
    innermost folder that holds it (`ownerFolder`), so an audiobook folder inside a music folder
    has its own choices. Removing a folder forgets its choices. Types are stored as switched
    **off**, so a new type that turns up later shows until unticked.
  - Audiobook folders got both options (the user asked for the rescan; file types came with
    the same window).
- **Mute:** the speaker icon beside every volume slider (`VolumeControl`: player bar, Now
  Playing, the mini player's pop-up) is a button: `PlayerModel.toggleMute` goes to 0 and
  remembers the volume; clicking again puts it back (to 50% if it was dragged to 0 by hand).
  The icon is in the highlight colour while muted.
- **Tests:** `test/folder_options_test.dart` (real scans of the sample files). Picture:
  `tool/ui_preview_test.dart` → `ui-folder-options.png`.

## Queue drawer, artist albums in place, Settings order (`feature/ui-feedback`, 0.1.26, asked for 29 Sep 19:13)
- **The user's choices:** the queue is a **drawer from the side on the phone too**; the tab is
  called **Folders & scanning**; the audiobook folders are shown **in both places** (the same
  setting); built **on top of 0.1.25**, to be released together.
- **Queue:** `openQueue` → `openQueueDrawer` (`queue_screen.dart`): a `showGeneralDialog` on the
  root navigator sliding in from the right, `QueuePanel` (min(420 px, 88% of the window)) with
  a title and ✕, `QueueList` inside. Closes on a tap outside, Esc, ✕ or a quick swipe right. The
  old full-page `QueueScreen` is gone.
- **Artist page** (`artist_screen.dart`, now stateful): albums are laid out row by row; tapping
  one (`AlbumCard.onTap`) opens `AlbumSongsPanel` under its row (title, year · songs · length,
  Play, Shuffle, Open album page, ✕, then the songs split by disc) and outlines the album
  (`highlighted`). Tapping it again or ✕ closes it; only one is open at a time. The right-click /
  press-and-hold menu gets **Open album page** (`SelectableCard.onOpenPage`) above Select.
- **Hover play:** `HoverPlayCover` (cards.dart) shows a round play button on an album cover while
  the mouse is over it, and plays the album (`playTracks(..., label: 'Album · …')`). It's on
  **every** album tile (Home, Library, Search, artist pages), not just the artist page, so it
  behaves the same everywhere; touch screens have no hover, so phones are unchanged.
- **Settings:** `SettingsPage` is in A–Z order by title (test enforces it). `library` keeps its
  code name but is shown as **Folders & scanning** ("Music and audiobook folders, and
  rescanning"). `AudiobookFoldersSection` (library_settings.dart) is the audiobook folder list,
  shown on both Folders & scanning (`library-book-folders`) and Audiobooks (`book-folders`).
  Rescan is enabled when either list has a folder. On wide windows Settings still opens on
  Folders & scanning.
- **Tests:** `test/ui_feedback_test.dart` (a stand-in player records what would play), plus the
  A–Z and search checks in `settings_test.dart`. Pictures: `flutter test tool/ui_preview_test.dart`.

## Advanced appearance (`feature/advanced-themes`, 0.1.25, asked for 29 Sep)
- **Started by another session** (16:43 on 29 Sep: theme model, readability checks, text sizes,
  corner choices, corners switched to `AppShape` in 22 files) and **finished by this one**
  after the user said "take over".
- **What the user sees:** Settings › Appearance › **Advanced**:
  - Saved themes: **New theme from the current one**, **New light theme** (starts from
    `lightStarter` "Daylight"), and Edit… / Duplicate… / Delete on each. Saved themes also appear
    as cards beside Default / Midnight / Forest / Your own.
  - The **theme editor** (`ThemeEditor`): name, a live preview, and eight colours with plain
    names (Background, Panels, Raised panels, Text, Grey text, Highlight, Slider track, Play
    button). The picker's "any" mode allows every colour. Warnings (`readabilityProblems`, the
    usual 4.5 / 3 contrast rules) say in plain words what may be hard to read; saving is still
    allowed. **Save and use** switches to it straight away.
  - **Deleting (asked for 29 Sep 17:13):** each saved-theme row has visible Edit and Delete buttons
    (plus ⋮ with Duplicate), and the editor has **Delete this theme** for themes already saved.
    All go through `confirmDeleteTheme` (asks first; says so when the theme is in use, which
    goes back to Default).
  - **Reset to default colours** under "Your own colours" (asked for the same time): clears
    `customAccent` / `customBackground` (`LibraryModel.resetCustomColours`), stays on "Your own",
    and shows a notice with **Undo** (`restoreCustomColours`). Greyed out when nothing was chosen.
  - **Text size** (Smaller 0.9 / Default / Larger 1.15 / Largest 1.3, on top of the system
    setting, via `withTextSize` in MaterialApp.builder) and **Corners** (Square / Slight / Default
    / Extra round → `AppShape.scale` 0 / 0.5 / 1 / 1.6, plus Material's cards, dialogs, buttons,
    menus and sheets in `buildTheme`).
- **Saved in settings.json** (so in backups): `savedThemes` (list of `{id: "saved:…", name,
  background, panels, raisedPanels, text, greyText, accent, sliderTrack, playButton}` as
  `#RRGGBB`), `textSize`, `cornerRoundness` (both clamped on load). `LibraryModel.saveTheme /
  deleteTheme / setLook`. Deleting the theme in use goes back to Default. A damaged saved theme is
  skipped.
- **Light themes:** `AppPalette.text` / `playButton` / `divider` / `faded()`; `buildTheme` pins
  every Material colour for saved and light themes (brightness light, text theme, icons,
  dividers), while the ready-made dark themes keep Material's in-between shades exactly as in
  0.1.24. Fixed white/black spots now use the theme: sidebar selection and divider, play button
  and its spinner, mini-player progress line, lyrics (sung/unsung lines), ticks and hearts on the
  highlight colour (`onAccent`).
- **Main.dart:** `Selector<LibraryModel, AppLook>` (`lookOfSettings`: palette, corners, text
  size); `RedrawOnThemeChange(look:)` redraws everything when any of them changes.
- **Tests:** `test/theme_test.dart` (325 tests in all on 29 Sep). In widget tests, don't `await`
  LibraryModel saves: Storage writes one file at a time and a write started inside the test's
  pretend clock never finishes, so a second awaited save hangs. The screen updates before the
  save anyway.
- **Pictures:** `flutter test tool/theme_preview_test.dart` now also draws a saved light theme with
  square corners and larger text, and the theme editor (`theme-light.png`, `theme-editor.png`).

## Updates (`feature/update-check`, 0.1.23, asked for 29 Sep)
- **The user's choices (29 Sep):** a "Check for updates" button in Settings › About **plus** a quiet
  check at most once a day with a switch to turn it off; on the phone, just **open the download
  page** (not download-and-install); on Windows it updates itself.
- **Where things are:** `services/update_checker.dart` (GitHub, versions, checksums, installer),
  `state/update_model.dart` (`UpdateModel`, `updates.json`: `autoCheck` + `lastCheck`; not in
  backups, it's per device), `ui/screens/settings/update_ui.dart` (About rows, the question
  dialog, the start-up notice). `main.dart` runs `checkIfDue()` 8 s after start; a find shows a
  SnackBar with **Update…** through `appMessengerKey` / `appNavigatorKey` on MaterialApp.
- **The check:** `GET api.github.com/repos/Jamesking96/HomeTunes/releases/latest` (unauthenticated;
  the repo's releases are public; 60 requests an hour per IP is plenty). Drafts and pre-releases are
  never offered. `isNewerVersion` compares the numbers (0.1.10 > 0.1.9) and ignores the `+build`.
  The dialog shows the release page's "What's new" part (text before the first `---`).
- **Windows, installed copy** (`unins000.exe` next to the exe): downloads
  `HomeTunes-Setup-<v>.exe` and `HomeTunes-<v>-SHA256SUMS.txt` from the release (only
  `https://github.com/Jamesking96/HomeTunes/releases/download/…` links), refuses and deletes the
  installer if its SHA-256 doesn't match, runs it detached with
  `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH=1`, then HomeTunes pauses,
  saves the book place and pending saves, and exits. `installer/hometunes.iss` has a `[Run]` entry
  with `Check: RelaunchAfterUpdate` (silent + `/RELAUNCH=1`) that starts HomeTunes again
  (`runasoriginaluser`). The checksum only protects against a broken or tampered download on the
  way; it comes from the same release, so it doesn't protect against a compromised GitHub account.
- **The zip copy and the phone** open the release page in the browser (`openInBrowser`: Windows
  `rundll32 url.dll,FileProtocolHandler`; Android the `openUrl` method on the `hometunes/app`
  channel in `MainActivity.kt`, https only).
- **First time:** 0.1.21 and 0.1.22 have no updater, so 0.1.23 has to be installed by hand once.
  From then on each release updates itself, as long as it's published with
  `tool/publish_release.ps1` (the asset names and the SHA256SUMS file are what the app looks for).
- **Tests:** `test/update_test.dart` (fake GitHub). Live check: `flutter test
  tool/probe_update_test.dart` reads the real latest release, downloads its installer and checks
  the checksum (nothing is installed). Passed on 29 Sep against v0.1.21.

## ✕ on notices (`feature/notice-close`, 0.1.30, asked for 29 Sep)
- **What the user asked for:** a close button on the notices at the bottom of the screen, next
  to Undo, to get rid of them quickly.
- **How:** one line in `buildTheme` (`ui/theme.dart`): `snackBarTheme: SnackBarThemeData(showCloseIcon:
  true)`, so all ~35 SnackBars get the ✕ (after any action like Undo) without touching each one,
  and new ones get it automatically. The ✕ just hides the notice; it never does the action.
  Don't add "Dismiss"/"OK" SnackBarActions: the ✕ already does that.
- **Tests:** `test/notice_close_test.dart` (default, Midnight, Forest and a light theme).
  Picture: `flutter test tool/notice_close_preview_test.dart` (loads the real icon font).

## Colour codes and sharing themes (`feature/theme-sharing`, 0.1.29, asked for 29 Sep)
- **What the user asked for:** type or paste a colour's hex code when choosing colours in
  Appearance, and export / import themes so they can be shared between friends.
- **Colour code box** (`_ColourPicker` in `appearance_settings.dart`): a "Colour code" field
  under the preview, with a paste button. `parseColourCode` (`ui/theme.dart`) accepts `#FF7A59`,
  `ff7a59`, `#F75`, `0xFF7A59`, with spaces/quotes/`;` around it. A typed code is returned
  exactly (`_typedColour`, not via HSL rounding). Sliders and suggestions rewrite the box. In
  Your own the usual limits still apply (bright highlight, dark background): a code outside
  them is adjusted and the helper line says "#FFFFFF changed to #xxxxxx so it stays easy to
  read". Enter in the box = "Use this colour".
- **Sharing** (`ui/screens/settings/theme_sharing.dart`): only the name and the eight colours
  (`sharedThemeJson`: `hometunesTheme: 1` + `AppPalette.toJson()` without `id`).
  - **Theme code:** `HOMETUNES-THEME:` + base64url of that JSON, no `=` padding, so chat apps
    keep it in one piece. `readSharedTheme` finds the code anywhere in pasted text (a whole
    message works), or reads raw JSON (a file).
  - **File:** `<name>.hometunes-theme`, pretty JSON, saved with `FilePicker.saveFile(bytes:)`
    like backups; opened with `FilePicker.pickFile`, refused over 64 KB.
  - **Checks:** 64 KB limit, every colour must be `#RRGGBB` (`AppPalette.fromJson`), the name has
    control characters removed and is cut to 40 characters, a newer `hometunesTheme` version
    that can't be read says "made by a newer version". Messages are plain English.
  - **Adding** (`addSharedTheme`): new id, name made unique ("Sunset (2)"); if a saved theme
    already has exactly the same colours, that one is used instead of adding a copy.
- **Where in the UI:** each saved theme's ⋮ has **Share…**; Your own has **Share these colours**
  (shared as "My colours"); Advanced has **Import a theme** (paste / Open a file… → preview with
  a readability note → **Add and use**).
- **Tests:** `test/theme_sharing_test.dart`. Pictures: `flutter test tool/theme_sharing_preview_test.dart`.

## What's new after an update (`feature/whats-new`, 0.1.28, asked for 29 Sep)
- **What the user asked for:** the first time the app opens after an update, a pop-up listing
  the changes between the old build and the new one, compiled from the "What's new in x"
  sections of the release pages.
- **How it knows:** `updates.json` gains `lastRunVersion`. `UpdateModel.load` compares it with
  this version: newer → `justUpdated`, `updatedFrom` = the old one. Nothing recorded but
  `updates.json` (0.1.23–0.1.27) or `settings.json` exists → an update from before 0.1.28, old
  version unknown, so only this version's notes are shown (`updatedFrom` null). Nothing at all →
  fresh install, nothing shown. An older version than last time → nothing shown. The version is
  saved as seen (`markWhatsNewSeen`) once the pop-up is closed, or straight away if there's
  nothing to show.
- **Where the text comes from:** `UpdateChecker.fetchReleases()` (`/releases?per_page=50`),
  then `releasesSince(all, from:, to:)` picks releases newer than `from` up to this version,
  newest first, skipping ones without a "What's new" section. `ReleaseInfo.notes` keeps the
  markdown (`whatsNewNotes`); `whatsNew` is still the plain version.
- **The pop-up** (`ui/screens/settings/whats_new_ui.dart`): `showWhatsNewAfterUpdate` runs 1.5 s
  after start from `main.dart`; `WhatsNewDialog` shows "Updated from x to y", then "Version y"
  + notes for each release, with **Open release page** and **OK**. `NotesText` draws `-` bullets
  (indented ones as ◦), `#` headings, `**bold**`, and drops `code` marks and link markup. If
  GitHub can't be reached, it still shows the version and why, with the release page button. A
  build with no published notes (a test build) shows nothing. The "Update to x?" dialog now
  uses `NotesText` too. **Settings › About › What's new in this version** shows this
  version's notes any time.
- **For releases:** because the pop-up reads the release pages, always publish with
  `-NotesFile` so the page starts with `## What's new in <version>`. When several versions
  go out as one release (0.1.25–0.1.28), put all of their changes in that one notes file.
- **Tests:** `test/whats_new_test.dart`. Picture: `flutter test tool/whats_new_preview_test.dart`.

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

## Editing several albums, books or songs (`multi-edit` branch, 0.1.11)
- **Selecting:**
  - `SelectionModel` holds one kind at a time (`SelectKind.songs/albums/books`). Ticking a
    different kind starts a new selection.
  - Album and book tiles use `SelectableCard` (in `cards.dart`). Right-click, or press and hold on
    a phone, opens a menu with Select and "Select all (n)". While selecting, a tap ticks or unticks
    the tile instead of opening it.
  - Each tile gets a `scope`: everything shown with it on that screen (Albums tab, artist page,
    search, Home shelves, Books grid in its current sort and filter). "Select all" ticks the scope.
  - `TrackTile` only shows tick boxes when songs are being selected.
- **The bar** (`_GroupSelectionBar` in `shell.dart`) shows "n albums/books selected", Select all,
  and **Edit albums / Edit books**. With one album it opens the normal album editor.
- **The `--:--` marker** (`differentMarker` in `edit_details.dart`):
  - A box whose value differs across what's being edited starts empty with `--:--` as its hint,
    and the note under it says "Different for each … – leave as --:-- to keep them".
  - Once something is typed, an undo button puts it back to `--:--`.
  - Only changed fields are saved, as TrackEdits on every track.
  - Songs multi-edit uses the same marker instead of "Mixed" (user's choice, 25 Sep).
- **Several albums** (`showEditDetails(..., albumCount: n)`):
  - The boxes are album artist, artist, year and genre, plus cover (choose image only).
  - **No album title**, because giving several albums the same title would merge them.
  - There are no online look-ups, and "Covers differ" is shown when they do.
- **Several books** (`showEditBooks`): the boxes are author, narrator, series, year and genre, plus
  cover. There's no title or number in series, and no online look-ups.
- **Tests:** `test/multi_edit_test.dart`.

## Favourite albums and audiobooks (`favourites` branch, 0.1.12)
- **Storage:** favourites are saved in `playlists.json` as `favouriteAlbums` and `favouriteBooks`.
  - **Both hold song/file ids, not album keys or book ids.** An album or book counts as a favourite
    when any of its songs is in the set.
  - That way they survive edits that regroup an album (album keys change), moved files (`remapIds`)
    and forgetting missing songs (`removeIds`). They also count in `referencedIds`, like playlists.
  - A backup merge keeps favourites from both sides.
- **Marking favourites:**
  - The heart button on the album page (`_FavouriteAlbumButton`) and on the book page.
  - "Add to / Remove from favourites" in the tile menu (right-click, or press and hold on a phone).
  - The heart in the selection bar. It removes them only when every selected one is already a
    favourite.
- **Seeing them:**
  - A small heart in the top-right of a favourite album or book cover.
  - The book "finished" tick moved to the cover's bottom-right corner to make room.
  - A Favourites filter: All / Favourites chips on Library › Albums, and a Favourites chip among the
    Books tab's state chips. The user chose filters only: no Home shelves and no separate page.
- **Tests:** `test/favourites_test.dart`.

## Quick actions and the Details page (`details-and-quick-edits` branch, 0.1.13)
- **Quick actions** (`ui/widgets/quick_actions.dart`, `albumActions` / `bookActions`):
  - The actions: Edit details…, Choose cover… (one picture for all), Find cover online… (one item
    only), Use the files' own cover(s) (only when a custom cover exists), Add to / Remove from
    favourites, and Details….
  - They appear in an album or book tile's right-click / press-and-hold menu, under Select and
    Select all.
  - While selecting, right-clicking a *ticked* tile shows the same actions for everything ticked,
    plus Select all / Stop selecting. Right-clicking an unticked tile just ticks it.
  - The selection bar's ⋮ shows them too.
  - Covers are set with `importCover` + `editMany(ids, TrackEdit(art:))`, like the editors.
- **Songs:** right-clicking a song row opens the same menu as its ⋮ button (`TrackMenuButton.items`),
  which now has **Details…**.
- **Details page** (`ui/screens/details_screen.dart`, logic in `services/media_details.dart`):
  - **Opened from:** Details… in the menus above, the ⓘ button on the album page, and "Details:
    where it comes from" in the book page's ⋮ menu.
  - **Shows:**
    - the folder(s), with "Show in folder" on Windows
    - file count, formats and size
    - why it's in Books or Music (`BookRules.why`, the same rules as `isBook`)
    - book series or narrator worked out from folder names
    - a table of every detail with **where it came from**
    - what the file's tags say (re-read now, plus sample rate and bit rate)
    - the files beside it that HomeTunes uses
  - With several files, the table covers the first file and each file expands to its own.
- **How a source is decided** (`inspectTrackNow`):
  - The scanned track (before edits) is compared with the track as shown. Anything different is
    "Your edit", with "File says:".
  - Otherwise the scanner's order is followed: book details file (`BookInfo`), the tags read again
    now, folder name, file name (`fallbackFromFileName`), stand-in ("Unknown Artist").
  - Covers: a picture beside it (`Sidecars.image`, or the folder cover names), built into the file
    (cached in `art/`), or your choice.
  - Length: from the tags, measured from the WAV header, or learned when played.
  - Server songs say "Music server".
  - If the file has changed since the scan, a detail can show "Couldn't tell".
- **Menus:** menu labels use `menuRow` (the text can wrap), because long labels overflowed the
  280 px menu.
- **Tests:** `test/details_test.dart`.

## Android fixes worth remembering
- **Playback stopping a while after locking the phone, with the screen still saying playing
  (0.1.20).** The brief pause media_kit makes while opening each song was passed to Android,
  which dropped the background-playback service; a locked phone can't start it again. A pause
  nobody asked for is now hidden from the media controls for 5 s, a watchdog restarts playback
  that stops by itself, and Settings › About › Playback log shows what happened. See
  `05_CODE_GUIDE.md` → "Fixed in 0.1.20".
- **Lock screen empty and playback stopping.** The cause was "You must specify an icon resource id
  to build a CustomAction". It's fixed by `res/raw/keep.xml`.
- **Scanning found nothing on Android 13+.** It must request READ_MEDIA_AUDIO alone. Asking for
  storage as well gave a false "granted". The app shows a banner when access is missing, and never
  scans without access, because that would wipe the library.
