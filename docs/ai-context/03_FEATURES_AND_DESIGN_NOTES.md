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
  is open but aren't saved; the Albums year sorts split the grid by decade. The logic is in
  `state/music_filters.dart` (no Flutter, so it's unit tested in `test/library_filters_test.dart`),
  the sheet in `ui/widgets/music_filter_sheet.dart`.
- **Edits.** The user can edit a song, a whole album, or a multi-selection. Covers can be picked
  from a file or found online (MusicBrainz / Cover Art Archive), and so can details. Edits are
  stored in `edits.json`; the files are untouched until **Settings → Your edits → Save edits into music files**
  (with an optional backup copy). Tags the app doesn't edit are kept, thanks to the patched writer.
- **Missing songs.** Songs whose files disappear are kept if they have edits or are in playlists or
  Liked Songs. If a file moves, it's matched to its old id. **Settings → Folders & scanning** can
  forget missing songs (the row only shows when there are some).
- **Song lengths.** When a file has no length in its tags, the real length is learned the first
  time it plays.
- **Backups** (`services/app_backup.dart`, **Settings → Backup & restore**). A `.htbackup` file
  holds settings, edits, playlists, library, listening, bookmarks, lyrics and equaliser data plus
  covers (the ones pulled out of music files only if "Include cover images from music files" is
  on; server covers are never included). It can be restored by merging (this device's settings
  win, folders are added, missing folders are dropped and reported) or replacing. HomeTunes saves
  `before-restore.htbackup` first. **The server password is never put in a backup** (since
  0.1.21, security review #6); after a restore the user may be asked to type it again. Files over
  256 MB, or that unpack to more than 512 MB, are refused.
- **Server.** Subsonic/OpenSubsonic streaming, with cover art from the server. Server audiobooks
  are assumed to work but still **need a review** (see `04_…`). See "Server sign-in and covers"
  below for how the password and covers are kept safe.

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
- **Swipe gestures (0.1.17).** On a touch screen, swiping the mini player or the Now Playing cover
  left/right goes to the next/previous song (`PlayerModel.swipe`; swiping back always goes to the
  previous song, it never just restarts). In a book it skips by the Audiobooks skip lengths and a
  short notice says how far. Mouse drags don't count. The switch is **Settings → Playback → Swipe
  gestures** (`swipeToSkip`, on by default).
- **Volume everywhere (0.1.22).** `VolumeControl` is in the desktop player bar
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
  5. a folder in the path is named like "audio books", counting only from the scanned folder
     down (since 0.1.16; a music folder at `D:\Audiobooks\Music` used to turn every song into a
     book)
  6. the file is inside one of the user's audiobook folders

  `BookRules.why` (`state/book_index.dart`) gives the rule that decided, in plain words, for the
  Details page. Server songs stop after rule 3.
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
  - Speed from 0.75× to 2.5× (`PlayerModel.speeds`), remembered per book; new books start at the
    "Speed for new books" setting.
  - Music queued while a book plays waits, and "Back to music" resumes it.
- **Sleep timer.**
  - A moon button beside play/pause, which can be hidden: one tap turns it on, another turns it
    off.
  - Books and music each have their own length in minutes (default 30), or "end of chapter" /
    "end of song".
  - The volume fades out ("Fade out before pausing", default 10 s, can be Off), then playback
    pauses and the book's place is saved.
- **Bookmarks** with notes.
- **Book editing** changes title, author, narrator, series and number, year, genre and cover, for
  all of a book's files at once. Online look-ups use Open Library.
- The Books page can **sort and filter** by title, author, narrator, series (in series order),
  recently listened or recently added. Covers can be square or tall (a setting).
- A book is **in progress** once there's a saved place in it and it isn't finished.
- Settings live in **Settings → Audiobooks**. This is the user's rule for everything book-related,
  except the sleep timer, which the user wanted in its own **Settings → Sleep timer** page (music and books).

## Book sidecar files (`services/book_sidecar.dart`)
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
  share a folder. On desktop, the book page shows "Open the book's PDF" (or EPUB). Since 0.1.21 it
  only opens a PDF/EPUB that really is inside one of the library folders.
- On Android these files are invisible (media permission), so nothing changes there.
- `sidecarStamp` hashes the sidecar names and modification times, so adding a file triggers a
  re-read. The first scan after upgrading re-reads everything once.

## Lyrics (plan phase 2)
- **Where they come from** (`LyricsModel`, first match wins):
  1. the user's lyrics (a TrackEdit; `""` = hidden)
  2. the file itself: the tags, or a `.lrc` file with the same name; timed beats plain
  3. lyrics found online before (`lyrics.json`, so they work offline)
  4. the server
  5. LRCLIB, if **Settings → Online lookups → Find lyrics online** is on
- A "nothing found" result is remembered for 14 days (`LyricsModel.retryAfter`). Books never go
  to LRCLIB automatically.
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

## Settings (0.1.9, reordered in 0.1.26)
- **Pages:** in A–Z order since 0.1.26: About, Appearance, Audiobooks, Backup & restore, Folders &
  scanning (code name `library`), Online lookups (`onlineLookups`), Playback, Servers (`server`),
  Sleep timer (`sleepTimer`), Your edits (`edits`) (`SettingsPage` in `settings_catalog.dart`).
  The pages are in `ui/screens/settings/`: `about_`, `appearance_`, `audiobook_`, `backup_`,
  `library_`, `online_`, `playback_`, `server_`, `sleep_` and `edits_settings.dart`.
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
- **Servers:** since 0.1.46, a list of servers in Music, Audiobooks and Videos sections (see
  "Servers page" below); the main music server and "Audiobooks from the music server"
  (`serverBooks`) are its first card's switches.
- **About** shows the version (package_info_plus) and the data folder, with "Open folder" on Windows.
  It also has **Check for updates** and **Check for updates automatically** (0.1.23), **What's new
  in this version** (0.1.28), **Playback log** (0.1.20) and **Licences** (0.1.31); see the
  sections below.

## Edit series (8 Oct 2026, 0.1.76, branch `feature/edit-series`)
- **Step 2 of the series work** (the user: "We might need a method to edit series like how we
  do with video collections"; "Go with your suggestions").
- **Edit series** (`screens/edit_series.dart`, `showEditSeries`, from the page's **Edit
  series** button `series-edit`, the ⋮ menu and the card's menu `series-menu-edit`): Name
  (`series-edit-name`), Author (`series-edit-author`; empty / unchanged leaves each book's own;
  with several authors the hint lists them), Description (`series-edit-description`), then the
  books: drag to reorder (`ReorderableListView`, `onReorderItem`), ✕ takes one out
  (`series-edit-remove:<id>`), **Add books…** (`series-edit-add`) picks from the rest of the
  library (search, tick, Add n). Save (`series-edit-save`) returns the new name and the open page
  follows it (SeriesScreen is stateful, `_edit`).
- **Saved** by `LibraryModel.editSeries` as TrackEdits through `editTracks` (files unchanged,
  like Edit book): a new name on every book; the author as artist + album artist; dragged order
  numbered 1, 2, 3… (added books too); otherwise added books numbered after the last book left;
  taken-out books get series "" and their number cleared. A rename moves `seriesInfo` and the
  sidebar link; the UI moves the favourite (`PlaylistsModel.renameFavouriteSeries`).
- **Series details:** `LibraryModel.seriesInfo` (settings.json `seriesInfo`: name →
  `description`, `picture`), `seriesDescription`, `setSeriesDescription`. The page shows the
  description (`series-description`) under the header.
- **Change picture** (`showSeriesPictureOptions`, button `series-change-picture`, menu
  `series-menu-picture`): Choose an image file… (copied into art/custom with `importCover`), Use
  one of its book covers… (`series-cover-pick:<id>`, stored as "book:<id>"), Use the automatic
  picture. `SeriesCover` draws it on the cards and the page; `seriesCoverBook` /
  `seriesPictureFile`. The custom-art clean-up keeps series pictures, and a restored backup
  drops a series picture outside the art folder (`AppBackup.sanitize`).
- **Tests:** `test/edit_series_test.dart` (rename with details and link, reorder, add / take out
  / author, picture + settings + backup, and on screen: rename with the page and favourite
  following, take out and add, the menu's picture choice).

## Audiobook series: a page, favourites and the sidebar (8 Oct 2026, 0.1.75, branch `feature/book-series`)
- **The user asked (8 Oct):** "Allow for the favouriting and adding audiobook series to be
  connected to the sidebar. We might need a method to edit series like how we do with video
  collections. Review what can be done here." The review proposed two steps; the user: "Go with
  your suggestions". This is step 1 (0.1.75); Edit series is step 2 (0.1.76).
- **A series** is still just the books sharing a series name: `BookSeries` / `seriesNamed` /
  `seriesOf` in book_index.dart (books in reading order, `authors` most books first,
  `coverBook` = first book with a cover).
- **Series page** (`screens/series_screen.dart`, `AppNav.openSeries(name)`): "AUDIOBOOK SERIES",
  picture, name, authors, "n books · x finished" (`series-counts`) and a progress bar; Play /
  Continue <book> / Listen again (`series-play`, the first book not finished; `playSeries`),
  heart (`series-favourite`), Add to sidebar (`QuickLinkButton`), Mark all as (not) finished
  (`series-mark-all`), a ⋮ menu; then one row per book (`series-book:<id>`: cover, "Book 2 ·
  3 hr left", a play button; the next book's line in the accent colour). A gone series says
  "Series not found". A book's page has "See the <series> series" (`book-open-series`).
- **Series tab:** cards instead of headings (`widgets/series_card.dart`, `SeriesCard`,
  `series-card:<name>`, the size of a book card: cover with the number of books, a heart if a
  favourite, a tick when all finished, a bar for how many are finished, "3 books · 1
  finished"). Tap opens the page; right-click / press and hold opens `showSeriesMenu` (Open,
  Play / Continue, favourites, sidebar, Mark all as finished; keys `series-menu-<what>`). Books
  not in a series follow under "Not in a series". The chips count series; its Favourites chip
  shows favourite series.
- **Favourites:** `PlaylistsModel.favouriteSeries` (names, playlists.json `favouriteSeries`,
  merged by `AppBackup.mergePlaylists`; `renameFavouriteSeries` for Edit series). The Favourites
  tab shows favourite series' cards under "Series", then the favourite books under "Books"; the
  sidebar's Favourite audiobooks opens it.
- **Sidebar:** `QuickLinkKind.series` (id = the name, icon `collections_bookmark_outlined`,
  "Series"); `openQuickLink` opens the page, or offers Remove link if the series is gone.
- **Tests:** `test/book_series_test.dart` (series order and authors, saved favourites and the
  backup merge, the link, the page: order, Continue, heart, sidebar, Mark all, gone) and
  `test/books_tabs_test.dart` (cards, favourite series, the card's menu).

## Audiobooks sub-tabs, like Music and Videos (8 Oct 2026, 0.1.74, branch `feature/audiobook-tabs`)
- **The user asked (8 Oct):** make the Audiobooks tab line up with Music and Videos, with
  sub-tabs instead of the chip buttons; then "include one at the start with sorts by series, and
  ensure that the sorting and filtering systems are taken into account just how are done in the
  other tabs".
- **Tabs** (`BookTab`): Series · All · In progress · Not started · Finished · Favourites, in the
  app bar's `TabBar` (`book-tabs`, scrollable, start-aligned like Your Library / Videos). Series is
  open to start with. The top bar keeps only Rescan; search, filter and sort moved into the tabs.
- **Each tab** (`_BookTab`, kept alive, its own state like `_FilteredTabState` in
  library_screen.dart): `MusicFilterBar` (box `library-title-filter`, matching title, author,
  narrator or series via `searchBookList`; Filter; Sort with Ascending / Descending), then the same
  chip row as Your Library (`All (n)` / `Favourites (n)`, keys `books-all-chip` /
  `books-favourites-chip`; not on the Favourites tab) and a removable chip per filter. Nothing
  matching: "No books match." + Clear filters; an empty tab says why (`books-empty-<tab>`).
- **Filters** now use the shared sheet (`showMusicFilterSheet`) with `bookFields`: Author,
  Narrator, Series, Genre, Decade. The old Books-only sheet is gone (`BookFilters` stays in
  book_index.dart, tested but unused by the screen).
- **Series tab:** `sortSeries` (book_index.dart): a heading per series (`series-heading:<name>`,
  with "n books"), books in series order, "Not in a series" always last. Sorts (`SeriesSort`):
  Series name, Author, Recently listened, Recently added, Most books; Descending flips the
  series order but keeps each series' reading order.
- **Sidebar Favourite audiobooks** opens the Favourites tab and clears its filters (GlobalKey).
- **Tests:** `test/books_tabs_test.dart` (sortSeries; tabs and their books; chips and box per
  tab; empty tab text; sidebar). Full suite and analyze clean.

## Rescan buttons on Your Library and Audiobooks (8 Oct 2026, 0.1.73, branch `feature/rescan-buttons`)
- **The user asked (8 Oct):** the Videos tab has a rescan button; add one for Audiobooks and
  Music too, as an easy, fast "rescan all".
- **Done:** `lib/ui/widgets/rescan_button.dart` (`RescanButton`, key `rescan-library`) in the top
  bar of Your Library and of Audiobooks (also on its empty page). It calls
  `LibraryModel.scanLocal`, the same rescan as Settings › Folders & scanning (music and
  audiobook folders together, since books can sit in music folders). Greyed out with "Add
  folders in Settings first" when there are none; a small spinner while scanning. Servers
  aren't rescanned by it (they have their own refresh in Settings › Servers).
- **Tests:** `test/rescan_button_test.dart`. Full suite 597, analyze clean.

## Now Playing in a small window, and a smallest window size (8 Oct 2026, 0.1.72, branch `feature/now-playing-small-window`)
- **The user asked (8 Oct):** when the window is made smaller while music plays: with a video
  showing, the play buttons move onto the video as an overlay (like the normal video player);
  with no video, the picture fades away and the buttons gradually get smaller. Also set a
  smallest window size and say where it is so they can change it.
- **Smallest window (PC):** `windows/runner/window_limits.h` (`kMinWindowWidth` 480,
  `kMinWindowHeight` 420; the whole window with its title bar, at 100 % display scale).
  `win32_window.cpp` answers `WM_GETMINMAXINFO` with those, scaled by the screen's DPI.
  Changing them needs a rebuild.
- **With a video** (`now_playing_screen.dart`): below `NowPlayingScreen.videoOnlyBelowHeight`
  (600, the page's own units) the page becomes just the video on black
  (`now-playing-video-only`). `MusicVideoView(overlayControls: true)` shows the full-screen
  style bar in the page (`_FullScreenBar(inPage: true)`): a Close (down arrow, top left,
  `music-video-close`) instead of nothing, and Full screen instead of Leave full screen. A
  `GlobalKey` keeps the video's player when the layout switches, so it doesn't restart.
- **Without a video:** the cover is the largest square that fits (`fittedCover`); below 156 it
  fades out, and below `NowPlayingScreen.smallestCover` (96) it's gone
  (`now-playing-no-cover`). The controls (`now-playing-controls`) are in a
  `FittedBox(scaleDown)` capped at the space left, so they only shrink when they don't fit.
- **Tests:** `test/now_playing_small_window_test.dart` (roomy: cover shown; 480 × 380: cover
  gone, controls fit, no overflow; in between). The video layouts need the video engine, so
  they aren't widget-tested. Full suite 595, analyze clean. Needs the user's eye on a PC.

## Fix: Next video sometimes replayed the same video (7 Oct 2026, 0.1.71, branch `fix/video-next-button`)
- **The user reported (7 Oct):** in a collection, pressing Next sometimes replayed the same
  video instead of going on.
- **Cause:** the video page built its previous / next buttons (and the Shift+N / Shift+P /
  media-key shortcuts) with the target worked out at build time. Full screen (media_kit) keeps
  the controls and keys it was opened with, so after one Next the saved target was the video now
  playing, and the next press opened it again.
- **Fix:** `_jump(forward:)` works the target out from `_id` when pressed; the buttons are
  `ValueListenableBuilder`s on `_shownId` (set in `_open`), so their greying-out and tooltips
  follow the video even in full screen; `_goTo` ignores the video already playing. The bottom
  bar / system controls' next and previous use `_jump` too.
- **Tests:** the video page needs the video engine, so this isn't widget-tested; the full suite
  (592) passes and `flutter analyze` is clean. Needs the user's check in full screen.

## Fix: video volume sliders follow the boost at once (6 Oct 2026, 0.1.70, branch `fix/video-volume-top`)
- **The user asked (6 Oct):** make sure the volume sliders update when the boost settings are
  changed.
- **Found:** the music sliders (`VolumeControl`) already did (`context.select` on
  `LibraryModel.maxVolume`; PlayerModel brings a louder volume down on any settings change). The
  two video sliders didn't: the bottom bar's (`_VideoVolume`, reads `NowWatching.maxVolume`,
  and NowWatching doesn't hear about settings) and the video player's own (`_VideoBarVolume`,
  rebuilt only by the volume stream). They kept the old top until the volume moved.
- **Fix:** both now `context.select<LibraryModel?, double?>((l) => l?.maxVolume)`, so they
  redraw as soon as the boost is changed. (The video page's `_followVolumeTop` still brings a
  louder volume down when the top is lowered.)
- **Tests:** `test/video_volume_top_test.dart` (the bottom bar's slider, key
  `video-bottom-volume`: 100 → 300 → 150 → 100).

## Ascending / descending for every sort (6 Oct 2026, 0.1.69, branch `feature/sort-direction`)
- **The user asked (6 Oct):** when sorting, add an ascending / descending option for each.
- **How:** `state/sort_order.dart`: `SortWords` (text, order, date, number, length) gives each
  sort the words for its two directions ("A to Z" / "Z to A", "Oldest first" / "Newest first",
  "Fewest first" / "Most first", "Shortest first" / "Longest first", "First to last" / "Last to
  first") and where it starts (dates, counts and lengths descending). `reversedIf` /
  `reverseGroupsIf` turn a list, or headed groups and what's in each, round.
- **Menu:** `SortMenu` (widgets/music_filter_sheet.dart, also used by `MusicFilterBar`): the sorts,
  a divider, then **Ascending (…)** and **Descending (…)**, ticked by direction. Screens keep
  `_reversed` (other way round from the sort's usual direction; picking a sort clears it), not
  saved, like the sort. The sort icon becomes ⇅ while reversed.
- **Where:** Your Library › Artists / Albums / Songs, Audiobooks (its own app-bar menu now uses
  `SortMenu`), Videos › Collections and All videos (Continue watching stays newest first).
- **Tidied:** "Name (Z–A)" (Artists) and "Year (oldest first)" (Albums) left the menus (the enum
  values stay for the sorting code and tests); "Year (newest first)" → "Year", "Longest first" →
  "Length", "Name (A–Z)" → "Name".
- **Tests:** `test/sort_order_test.dart`; `library_filters_test.dart` checks Year + Ascending
  and that a new sort starts in its usual direction.

## A video in a small window (6 Oct 2026, 0.1.68, branch `feature/small-window-video`)
- **The user asked (6 Oct):** when the UI is scaled down and a video is present, prioritise the
  video's size over text and controls; those scale down to a value just small enough that
  they're still usable.
- **How (computer only; phones unchanged):** on the video page (`_VideoPageState.build`), from
  the real window size (`View.of(context)`, not the shrunk layout size):
  `WindowScale.squeeze(window)` (0 at 1200 × 760 and above, 1 at 760 × 520 and below).
  - The video's height cap goes from 70 % of the page to 85 % (`WindowScale.videoShare`).
  - The title, facts and button rows under it are wrapped in `ShrinkToWidth` (laid out wider,
    drawn smaller with a FittedBox, so no gap is left and clicks land) at
    `WindowScale.videoInfoScale(window, appFactor:)`: on screen, together with the whole app's
    own shrink (when Shrink to fit small windows is on), they go from 100 % down to
    `smallestVideoInfo` = 75 % (about 10–11 px text). With the app shrink on, that's only 6 %
    more than the app's own 80 %.
  - The video's own control bar is left as it is (already shrunk with the app).
- **Tests:** `test/small_window_video_test.dart` (the sizes, and ShrinkToWidth's drawing and
  clicks). The video page itself isn't widget-tested (needs the video engine).

## Playlist icons (6 Oct 2026, 0.1.67, branch `feature/playlist-icons`)
- **The user asked (6 Oct):** an option on playlists to customise their icons. They chose a
  built-in icon + colour, or a picture.
- **Saved:** `Playlist.iconName` (a name from `playlistIcons` in `widgets/playlist_art.dart`;
  names must never change once used), `iconColour` (ARGB, null = the accent), `iconImage` (a
  plain file name; `fromJson` refuses anything with a path in it). In playlists.json.
- **Pictures:** `PlaylistsModel.setPicture` copies the chosen file into
  `art/custom/playlists/<md5>.<ext>` (`pictureDir`): under `custom` so backups carry it, in a
  sub-folder so LibraryModel's custom-cover tidy-up (which only lists art/custom itself) leaves
  it alone. `_tidyPictures` deletes ones no playlist uses (after setIcon / setPicture /
  clearIcon / delete). Backup merge (`AppBackup.mergePlaylists`): a playlist with no icon takes
  the backup's.
- **Shown by `PlaylistArt`:** picture, else `PlaylistIconTile` (the icon on a gradient of the
  colour, white or black by brightness), else the first song's cover as before. Used in the
  Library's Playlists tab, the playlist page's header (click it to change), and Home's quick
  tiles (`_QuickTile.art`). The sidebar quick link uses the icon (`quickLinkIconFor`).
- **Changing:** `showPlaylistIconPicker` (playlist page ⋮ › **Change icon…**, or a click on its
  picture): an icon grid, colour swatches (first = the app's colour), **Choose a picture…**,
  **Use the first song's cover** (when it has its own).
- **Tests:** `test/playlist_icons_test.dart`.

## Special seasons (6 Oct 2026, 0.1.66, branch `feature/special-seasons`)
- **The user asked (6 Oct):** mark seasons as special with their own titles that they can
  customise and apply. Their choices: title + badge + listed last + skipped by Up next / playing
  on; titles from a reusable list in Settings (typing a new one adds it).
- **Marks:** `VideoLibraryModel._specialSeasons` (collection key → season "3" / "1.2" → title),
  videos.json `specialSeasons`, moved with a collection rename, merged by backups
  (`app_backup.dart`, the backup's win). `setSpecialSeason(c, season, title|null, sub:)`,
  `specialTitleOf`, `isSpecialGroup`. Season 0 and extras can't be marked.
- **How it shows:** `_rebuild` puts the title on each video in a marked season
  (`VideoItem.specialTitle`, via `withSpecial`; not saved with the video). `groupOf` then gives
  the title as the heading (seasons with the same title share it); `sortForCollection` ranks
  them with Season 0 "Specials" (after normal seasons and named parts, before extras), by season
  number. `_GroupHeading` shows a "Special" badge (`SpecialBadge`). The season-title pencil
  isn't offered on a special group.
- **Playing:** `after()` doesn't run from a normal episode into a special one (within specials
  it plays on); `nextUp()` leaves specials out unless there's nothing else (so Home's Up next
  and the collection's "Up next" skip them).
- **UI:** a season heading's right-click menu (`showVideoGroupMenu`, `onSpecial`) › **Mark as
  special…** (`showSpecialSeasonDialog`, `screens/special_seasons.dart`: chips from the list and
  a text box) or **Not special any more** (`unmarkSpecialGroup`, every season in the group).
  Settings › Videos › **Special season titles** (`SpecialSeasonTitlesSection`,
  `special-season-titles`): `LibraryModel.specialSeasonTitles` (default Specials, OVA, Movies,
  Bonus episodes; settings.json `specialSeasonTitles`; blanks and repeats dropped).
- **Tests:** `test/special_seasons_test.dart`.

## Volume percentage bubble (6 Oct 2026, 0.1.65, branch `feature/volume-percent`)
- **The user asked (6 Oct):** show what % the volume is on above the volume slider, with a
  setting to turn it off. They chose "only while adjusting" (not always shown).
- **How:** `widgets/volume_slider.dart`, `VolumeSlider` (a `Slider` plus an `OverlayPortal`
  bubble following the handle through a `LayerLink`, so pop-ups and video controls can't clip
  it). It shows while the slider is held, and for `VolumeSlider.showFor` (1 s) after any other
  change to the value (wheel, touchpad, mute, keys: noticed in `didUpdateWidget`). Used by
  `VolumeControl` (player bar, Now Playing, phone pop-up, full-screen music video), the video
  bottom bar (`_VideoVolume`) and the video player's own bar (`_VideoBarVolume`). Handle
  position: the track runs inside the larger of the handle's and its glow's radius.
- **Setting:** Settings › Playback › **Show the volume percentage** (`volume-percent`,
  `LibraryModel.showVolumePercent`, on by default, settings.json `showVolumePercent`).
- **Tests:** `test/volume_percent_test.dart`.

## Quick links in the sidebar (6 Oct 2026, 0.1.64, branch `feature/sidebar-quick-links`)
- **The user asked (6 Oct):** add and remove more "quick links" in the computer's sidebar, below
  Liked Songs and the favourites.
- **What can be a link:** an album, artist, audiobook, video collection or video
  (`models/quick_link.dart`: `QuickLink(kind, id, label)`; the id is an album's key, an
  artist's or collection's name, a book's or video's id; the label is the name when it was
  added). Kept in settings.json as `quickLinks`, in the order added (`LibraryModel.quickLinks`,
  `addQuickLink`, `removeQuickLink`, `toggleQuickLink`, `isQuickLink`). Damaged entries are
  skipped when loading.
- **Adding / removing:** a bookmark button (`QuickLinkButton`, "Add to sidebar" / "In the
  sidebar") at the top of an album's, artist's, audiobook's and collection's page; "Add to
  sidebar" / "Remove from sidebar" in the right-click / long-press menus of albums, audiobooks
  (`quick_actions.dart`, one item selected), collections and videos (`videos_screen.dart`); and a
  right-click (or long-press) on the link in the sidebar ("Remove from sidebar").
- **In the sidebar** (`widgets/sidebar.dart`): straight under Favourite videos, each with its
  kind's icon; in a scrolling list with the playlists under them (a divider between), so a long
  list never pushes anything off. Folded to icons, they're icons with the name as the tooltip.
  With none, a dim line says how to add one. A click opens it (`openQuickLink`); something no
  longer in the library says so, with a **Remove link** button.
- **Playlists too (6 Oct, the user's follow-up, build 0.1.64+66):** `QuickLinkKind.playlist`
  (id = the playlist's id). Added with the bookmark button on a playlist's page, or a
  right-click / press and hold on a playlist in the sidebar's list or the Library's Playlists
  tab (`QuickLinkMenu`, the shared add-or-remove menu, also used on the links themselves). The
  link shows the playlist's current name (`quickLinkLabel`), so a rename follows. Deleting the
  playlist takes its link off too. A pinned playlist still appears in the playlists list below.
- **Phone:** there's no sidebar on a phone, so the links only show in the computer layout. The
  buttons and menu items are still there on a phone (and a wide tablet gets the sidebar).
  settings.json is per device, so links are per device. Open question for the user: hide the
  buttons on a phone, or show the links there too (e.g. on Home)?
- **Tests:** `test/quick_links_test.dart`.

## Sleep timer for videos (6 Oct 2026, 0.1.63, branch `feature/video-sleep-timer`)
- **The user asked (6 Oct):** the sleep timer in the normal video player.
- **How:** `state/video_sleep_timer.dart`, `VideoSleepTimer` (a ChangeNotifier provided in
  `main.dart`), separate from the music's `SleepTimer` (which is tied to songs and chapters). It
  works on whatever video is in charge through `VideoSleepTarget` (`WatchingSleepTarget` over
  `NowWatching`; tests use a fake). Length: **Settings › Sleep timer › Timer length for videos**
  (`LibraryModel.sleepVideoMinutes`, default 30; `sleepAtEnd` = "End of video",
  `sleep-videos`). The fade and "Show sleep timer button" are shared with music.
- **End of video** pauses in the last half second (`endMargin`), so the video never reaches its
  end and the next episode's "Up next" countdown doesn't start; if the video changes anyway, the
  new one is paused. Closing the video page stops the timer. Pausing saves the place (the video
  page saves on every pause).
- **The moon** (`widgets/video_sleep_button.dart`, `VideoSleepTimerButton`): in the video
  player's own bar on the computer and the phone (normal and full screen, in the chosen button
  colour and size) and in the bottom bar's video controls (`VideoTransportControls`). On, it's
  a pill with the time left; a tap turns it off.
- **Tests:** `test/video_sleep_timer_test.dart`.

## Volume boost through the volume sliders (5 Oct 2026, 0.1.62, released in v0.1.62)
- **The user asked (5 Oct, after 0.1.61):** with the boost on, the Settings slider should only
  say how far the volume can go, and the normal volume sliders should run up to that.
- **Now:** `LibraryModel.maxVolume` = 100, or the boost's percentage while it's on
  (`maxVolumeFor`). Every volume slider runs 0 → `maxVolume`: the player bar / Now Playing /
  phone pop-up (`VolumeControl`, `VolumeButton`; the wheel and touchpad too,
  `afterWheel(max:)`), the video bottom bar (`_VideoVolume`, `NowWatching.maxVolume` via the
  `VolumeTop` interface on `MediaKitTransport`), and the video player's own bar, where media_kit's
  volume button (fixed at 100) is replaced by `_VideoBarVolume`; ↑ ↓ and the wheel over a video
  step 5 on the same scale (`stepEngineVolume`).
- **Sound:** up to 100 the engine gets the slider value as before (nothing changes for normal
  listening). Above 100 it gets 100 × ∛(value / 100) (`engineVolume`; mpv's volume is cubic),
  so 500 % is 5 × as loud; `volume-max` is raised to 200 on both players. The video player keeps
  its volume in the engine, so its sliders read it back with `sliderVolume`. The 0.1.61 fixed
  boost (cube-root multiplier for music, `replaygain-fallback` dB for videos) is gone.
- **Turning the boost off or lowering its top** brings a louder volume down to it
  (`PlayerModel._applyEngineSettings`, the video page's `_followVolumeTop`).
- **Settings text:** "Every volume slider now goes up to N%. Past 100% is louder than normal."
- **Tests:** `test/volume_boost_test.dart` (the slider top, the volume maths both ways, steps,
  the Settings page, the wheel past 100).

## Volume boost (5 Oct 2026, 0.1.61, reworked in 0.1.62, released in v0.1.62)
- **The user asked (5 Oct):** a volume boost like VLC's (up to 500 %) in Settings: a switch and
  a scale for how much, off and 100 % by default.
- **Settings › Playback › Volume boost** (`volume-boost`): a switch and a slider, 100–500 % in
  25 % steps (the slider only moves while it's on), with a note that very high boosts can
  crackle. `LibraryModel.volumeBoost` / `volumeBoostPercent` (settings.json, clamped),
  `setVolumeBoost`. Applies to music, audiobooks and videos, straight away.
- **How** (`models/volume_boost.dart`): 500 % = 5 × the sound level (+14 dB). The engine is
  mpv 0.36 (no `volume-gain`), and a volume filter in the lavfi graph stalled playback before,
  so:
  - music / books (`PlayerModel`): mpv's volume, which is cubic, is multiplied by the cube root
    of the boost (`boostVolumeScale`; 500 % → ×1.71), and `volume-max` is raised to 200
    (`engineVolumeMax`) the first time engine settings are applied (mpv stops at 130
    otherwise). `_sendVolume` sends volume × equaliser level × boost; `_applyEngineSettings`
    resends when the boost changes (`_appliedBoost`).
  - videos (video page): media_kit's controls set that player's volume directly, so the boost
    goes into `replaygain-fallback` in dB (`boostDb`) with the videos' equaliser level; the page
    now listens to LibraryModel for changes. (mpv applies the fallback gain without its
    clipping guard.)
  - music videos are muted, so nothing changes there.
- **Not heard yet:** tests check the maths, the setting and the Settings page; the user should
  listen on the PC and the phone.
- **Tests:** `test/volume_boost_test.dart`.

## Always on top (5 Oct 2026, 0.1.60, released in v0.1.62)
- **The user asked (5 Oct):** an "Always on top" toggle that's always there and easy to click on
  and off, shown in whatever way suits each page.
- **What it does:** keeps the PC window above other windows. Only a computer window can, so the
  button only shows on Windows (`WindowPin.available`; tests set `WindowPin.debugAvailable`).
  Remembered (`LibraryModel.alwaysOnTop`, settings.json, `setAlwaysOnTop`) and put back at
  start-up (`load()` calls `WindowPin.set`).
- **How:** `windows/runner/flutter_window.cpp` has a "hometunes/window" method channel;
  `setAlwaysOnTop(bool)` calls `SetWindowPos(HWND_TOPMOST / HWND_NOTOPMOST, no move / size /
  focus)` on the app's window (`services/window_pin.dart` calls it). media_kit's full screen
  moves the window with `HWND_TOP`, which keeps a topmost window topmost, so they don't clash.
- **Where the pin is** (`widgets/always_on_top_button.dart`, `always-on-top`; outline pin = off,
  filled accent pin = on, tooltips "Keep HomeTunes on top of other windows" / "Always on top is
  on (click to turn it off)"):
  - the right end of the player bar along the bottom (`_PlayerBarWithPin` in `shell.dart`), for
    music and videos, under every tab and page; in a narrow window, beside the tab bar
    (`Shell._withPin`);
  - Now Playing's top bar and the Details pages' app bars (they cover the player bar);
  - full screen: a round pin top-right on videos (media_kit's top row, opposite Leave full
    screen) and on music videos (`round: true`).
- **Tests:** `test/always_on_top_test.dart` (on / off, remembered, round, none on a phone).

## Video buttons on the picture (5 Oct 2026, 0.1.59, released in v0.1.62)
- **The user asked (5 Oct):** Enlarge and Full screen on the video itself, like Shrink and the
  full-screen button when enlarged, without removing the buttons below the video; the same on
  the phone; and a full-screen music video should have the same controls as a normal video
  (the user picked "like a normal video": progress bar, skips, volume, over just the round
  buttons).
- **Video page** (`video_player_screen.dart`): in the normal layout the picture has a round
  **Enlarge** `_OverlayButton` top-left (`video-overlay-enlarge`), always shown like the enlarged
  view's Shrink. A round Full screen top-right was tried and taken off (build +60, the user's
  choice): the player's own Full screen button is already in the bottom corner. The enlarged
  view's top-right Full screen went for the same reason. In full screen, media_kit's `topButtonBar` (new `top:` parameter
  of `desktopControlsTheme` / `phoneControlsTheme`, only for the `fullscreen:` theme) has a
  round **Leave full screen** (`video-leave-fullscreen`) that shows and hides with the controls.
  Same code on PC and phone.
- **Music video full screen** (`music_video_view.dart`, `_FullScreenBar`): title and artist, the
  song's `SeekBar` (compact, white times via the new `timeColor`), skip back / forward by
  Settings › Videos' amounts (`PlayerModel.skipBy`; white `SkipIcon`s via its new `color`),
  previous / play-pause / next, `VolumeControl` when the bar is 640 px or wider (phones use their
  volume buttons), and Leave full screen; the controls shrink to fit narrow screens. ← → skip
  too. A touch or drag on the buttons keeps them up (a `Listener`), so dragging the progress bar
  on a phone doesn't hide them.
- **Tests:** the video page and music video need the real engine, so `test/video_buttons_test.dart`
  checks the pieces (the top button row only in full screen, white skip icons). Try on the PC and
  the phone.

## Music videos back to the usual drawing (5 Oct 2026, 0.1.58, released in v0.1.58)
- **What the third log showed (5 Oct, 0.1.57, the user's phone):**
  - *Normal video* (1080p HEVC, now `mediacodec` + `mediacodec_embed`): **no pictures dropped**
    in a minute (10 in 30 s before). "Paused to load 5 times" in the first 30 s: the user said
    they skipped by a few seconds, and each skip pauses to load. Read ahead 136 s.
  - *Music video* (same drawing): much worse: jumps with the video **18.7 s behind**, then
    13.3 s behind and 4.5–55.5 s ahead. This player has no sound (`aid=no`); with no sound to
    keep time by, drawing straight from the chip let the video freeze and then race ahead.
    Skipping the song a few seconds can't explain drifts that size. The learnt lead
    (`learnSeekLead`) also learnt from those wild landings.
- **Fix:** music videos always use media_kit's own drawing (`musicVideoDrawing` in
  `video_drawing.dart`; in 0.1.56 it only dropped 1 picture a minute); the Settings switch now
  only affects the Videos tab's player. `learnSeekLead` ignores landings more than
  `videoSyncTolerance` (2 s) out, and the lead is at most 2 s (`maxSeekLead`, was 4 s).
- **Log:** skips are noted ("you skipped or moved it n times", `VideoStats.moved`, from the
  video page's position stream: a jump over 1.5 s between readings, not in the 2.5 s after
  opening), so pauses to load after a skip aren't mistaken for stutter.
- **Tests:** `test/music_video_test.dart` (far-off landings teach nothing, 2 s cap),
  `test/video_stats_test.dart` (skips, `musicVideoDrawing`).

## Smoother video drawing on phones (5 Oct 2026, 0.1.57, released in v0.1.58)
- **What the second log showed (5 Oct, 0.1.56, the user's phone):**
  - *Music video* (1080p H.264 24 fps, `mediacodec-copy`, `gpu`): 1 picture dropped, but still
    **4 jumps back into step in 30 s** and the app slow to draw 16 times. The likely cause: a
    jump (a precise seek) decodes from the last keyframe, which can be seconds back in a music
    video; the song plays on meanwhile, so the video lands behind, past the 1.5 s limit again,
    and jumps again.
  - *Normal video* (1080p HEVC 23.98 fps, `mediacodec-copy`, `gpu`): 10 pictures dropped, **all
    by the screen** (decoder 0), read ahead 130 s. Decoding and file reading are fine, so
    buffering wouldn't help; the loss is in the copy-then-redraw path. That 30 s also included
    the app going to the background and back, which by itself drops pictures and redraws
    everything.
- **Music video fixes** (`music_video_view.dart`): catch-up by speed is quicker (up to 20 %,
  aiming at ~2 s; was 10 % / 3 s); jumps only past 2 s (`videoSyncTolerance`, was 1.5 s); each
  jump aims ahead of the song by a learnt lead (`learnSeekLead`: after a jump, the first check
  adds however far the video still is behind; overshooting shrinks it; 0–4 s, `maxSeekLead`;
  kept for the next songs).
- **Drawing straight from the video chip on the phone** (`services/video_drawing.dart`):
  `VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')` on Android for
  both the video page and music videos, instead of media_kit's `gpu` + `mediacodec-copy`. Lost:
  the engine can't draw on top of the picture (the phone already draws text subtitles itself);
  a format the chip can't decode may show black. **Settings › Videos › "Smoother video on
  phones"** (`LibraryModel.videoDirectDrawing`, default on, `video-direct`) turns it off; it
  applies the next time a video opens; greyed out off Android. Drawing at screen size isn't
  possible on Android (media_kit's `setSize` throws there).
- **Log additions** (`video_stats.dart`): the jumps' distances ("jumped back into step 4 times
  (video behind by 1.8–2.6 s)", `jumpDetail`), the worst slow frame and whether building or
  drawing made the slow frames slow ("app slow to draw 16 times (worst 85 ms, mostly drawing)",
  `slowDetail`, Flutter's `buildDuration` / `rasterDuration`), and "the app was out of sight for
  part of it" when it was hidden during those 30 s. The start line says "drawing: straight from
  the video chip (mediacodec_embed)" (`describeDrawing`).
- **Next:** the user's next log decides: if the app is still slow to draw while a video plays,
  look at what redraws (media_kit's controls rebuild on each position tick even when hidden).
- **Tests:** `test/music_video_test.dart` ("a jump aims ahead by what the last jumps lacked",
  updated speeds), `test/video_stats_test.dart` (new line parts, "how videos are drawn"),
  `test/settings_test.dart` (the new setting is on Settings › Videos).

## Smoother music videos (5 Oct 2026, 0.1.56, released in v0.1.58)
- **What the first log showed (5 Oct, the user's phone, Android, 9 cores):** a 1080p H.264
  24 fps music video, decoded by the video chip with copying (`mediacodec-copy`, drawing `gpu`):
  **no pictures dropped at all**, but "waited for the file" 3 times in 30 s and 6 times in
  52 s. media_kit's buffering stream turns true whenever mpv's `core-idle` does, which includes
  every seek; so those "waits" were HomeTunes' own jumps back into step (`videoSyncTolerance`
  was 0.4 s, checked twice a second, 2 s pause after each jump). Each jump freezes the picture
  for a moment: one every ~9 s on the phone, which was the stutter. Decoding was fine.
- **Fix:** small drifts are caught up with speed: `videoSyncRate` plays the silent video up to
  10 % faster (behind) or slower (ahead), aiming to close the gap in ~3 s, back to the song's
  speed (`PlayerModel.speed`) once within 0.1 s (`videoInStep`); the rate is only changed when it
  moves by 0.01 or more. Only drifts over 1.5 s (`videoSyncTolerance`, was 0.4 s) jump: after a
  seek within the song, repeat-one, or coming back into sight. After a jump, checks wait until
  the engine has finished settling (buffering, up to 3 s). A new file starts at the song's speed.
- **Log changes:** "waited for the file" is now **"paused to load"** (it covers any pause to get
  pictures ready); the pause after opening a file or after a jump isn't counted (2.5 s quiet);
  the jumps are counted on their own, "jumped back into step n times" (`VideoStats.jumped`).
- **Next, if the user's next log shows normal videos stuttering:** the plan's steps 2/3 (video
  chip without copying, drawing at screen size), then buffering. No log of a normal video yet.
- **Tests:** `test/music_video_test.dart` ("a small drift is caught up with speed, not a jump"),
  `test/video_stats_test.dart`.

## Video playback stats (5 Oct 2026, 0.1.55, released in v0.1.58)
- **Why:** the user said videos and music videos are sometimes laggy, more on the phone but on
  the PC too, and asked about pre-buffering. Agreed plan (5 Oct): measure first, then, in order,
  make the video chip work properly, draw at screen size, smooth the music video syncing,
  pre-buffering / opening the next one early (mainly for network shares or servers), and fewer
  redraws while a video plays. This version is step 1.
- **What it logs** (`services/video_stats.dart`, in Settings › About › Playback log):
  - `Device: android … , N processor cores` once per run;
  - `Video started: <name> · 3840×2160 · HEVC 10-bit · 23.98 fps · decoding: … · drawing: gpu`
    about 3 s after a file opens (from mpv `video-params/w|h`, `video-format`,
    `video-params/pixelformat`, `container-fps`, `hwdec-current`, `current-vo`). Decoding in
    plain words: "software (main processor)", "video chip (…)" or "video chip, copied before
    drawing (…-copy)";
  - every 30 s while playing, **only if something went wrong**: `Video stutter in the last 30 s:
    N pictures dropped (decoder a, screen b) · waited for the file n times · app slow to draw n
    times · read ahead x s` (`decoder-frame-drop-count`, `frame-drop-count`, the player's
    buffering stream, Flutter frame timings over 34 ms, `demuxer-cache-duration`);
  - `Video finished: <name> · played m:ss · smooth` (or what went wrong) when it closes or the
    next file starts.
  The same for music videos ("Music video …"). Sampling every 5 s, only while playing; nothing
  under `flutter test`.
- **Known from reading the engine's code (5 Oct):** on Android media_kit_video 2.0.1 defaults
  to `vo=gpu` with `hwdec=auto-safe` (software in an emulator); on Windows `vo=libmpv`,
  `hwdec=auto`. HomeTunes didn't change either. `VideoController.setSize` can draw at a smaller
  size (step 3). Music videos are moved back into step whenever they drift more than 400 ms
  (`videoSyncTolerance`), each move a seek (step 4).
- **Tests:** `test/video_stats_test.dart`.

## One song's album edit no longer renames the album (3 Oct 2026, 0.1.54, released as v0.1.54)
- **What the user reported:** "when 1 song has it's album edited it renames the whole album rather
  than just updates that song."
- **Cause:** the single-song editor (`edit_details.dart`) offers "Also update the other N songs on
  "…"" whenever an album-wide detail changes (album, album artist, year, genre, cover). The box
  started **ticked** (`_updateAlbum = true`), so typing a new album name and pressing Save gave
  every song on the album the new name: the whole album was renamed.
- **Fix:** the box's starting state now depends on what changed (`_updateAlbum =>
  _updateAlbumChoice ?? !_movesSong`). If the album name or album artist changed
  (`_movesSong`), it starts **unticked** and only that song moves; the subtitle adds "Leave
  unticked to move just this song." Year, genre or cover changes alone still start ticked, as
  before. Once the user clicks the box, their choice sticks (`_updateAlbumChoice`). Ticking it
  still renames the whole album.
- **Tests:** three "one song: …" cases in `test/multi_edit_test.dart` (moves just that song;
  ticking renames the album; genre change still ticked). The box is below the fold in the test
  window: find it with `skipOffstage: false` and `ensureVisible` before tapping.

## Artist pictures (2 Oct 2026, 0.1.53, released in v0.1.53)
- **What the user asked for:** "Allow the artists page to be customised too, I want to be able to
  change the image that's used."
- **How it works:** artists still show their first album's cover by default. **Change picture…**
  is on the artist page (click the round picture, or the picture button beside Play / Shuffle)
  and in the right-click / press-and-hold menu of any artist card (Home, Search, the Artists
  tab's grid) and the Artists tab's list rows. Choices: **Choose an image file…** (copied into
  `art/custom/` with `importCover`, like album covers), **Use one of their album covers…** (a grid
  of their albums; the one in use has a ring), and **Use the automatic picture** (only when
  something was chosen; also in the right-click menu). Every artist picture follows straight
  away (`Artwork(artist: …)` watches `artistPictures[name]`).
- **Stored:** `LibraryModel.artistPictures` (settings.json `artistPictures`, by artist name): a
  file path, or `album:<album key>`. A file must be inside the art folder to be used
  (`artistPictureFile`); `_removeUnusedCustomArt` keeps files an artist uses; backups carry the
  file (art/custom always goes in) and `AppBackup.sanitize` drops a restored path outside the
  art folder. Keyed by name, so renaming an artist (by editing album artist) starts them on the
  automatic picture again; a chosen album that's gone falls back to the first album.
- **Not done (could be next):** searching online for artist photos (MusicBrainz has none; would
  need Wikipedia / Wikimedia or similar), and other artist customisation (renaming happens
  through album artist edits).
- **Code:** `ui/widgets/artist_picture.dart`, `LibraryModel` (`artistAlbumArt`,
  `artistPictureFile`, `artistImage`, `hasArtistPicture`, `setArtistPicture`), `Artwork.artist`,
  `ArtistCard` (menu), `artist_screen.dart`, `library_screen.dart`. Tests:
  `test/artist_pictures_test.dart`.

## Artists tab: list or grid (2 Oct 2026, 0.1.52, released in v0.1.53)
- **What the user asked for:** "The Artists tab in Your Library should have a list and a grid view
  mode".
- **How it works:** a button in the Artists tab's filter bar, before Filter and Sort (grid icon
  "Show as a grid" / list icon "Show as a list"). The list is as before (round picture, name,
  "3 albums · 41 songs"). The grid uses the round `ArtistCard` (as on Home and Search) with the
  same counts under the name, as many columns as fit (`gridColumns`, like the Albums tab). The
  title box, chips, filters and sort apply to both. The choice is kept in settings.json
  (`artistsGrid`, default list), so it's in backups and survives restarts.
- **Code:** `library_screen.dart` (`_ArtistsTabState`, keys `artists-view`, `artists-list`,
  `artists-grid`), `LibraryModel.artistsGrid` / `setArtistsGrid`, `MusicFilterBar.actions`,
  `ArtistCard.subtitle`. Test: "Artists: list and grid views" in `test/library_filters_test.dart`.

## Update check at start-up (2 Oct 2026, 0.1.51, released in v0.1.53)
- **What the user asked for:** "Update the check for updates to be on startup not once per day".
- **How it works:** while Settings › About › "Check for updates automatically" is on, HomeTunes
  looks for a newer version every time it opens (it used to wait 24 h between checks). It runs
  in main.dart straight after the internet check (about 1.2 s after start), in the background,
  only if the internet was reachable, so it never adds a second message when offline. A newer
  version still shows the notice with **Update…**. The switch's text now says "Each time
  HomeTunes opens…".
- **Code:** `UpdateModel.isDue` is just `autoCheck`; `checkIfDue` became `checkAtStart`;
  `checkEvery` is gone. `lastCheck` is still saved (shown as "Last checked…"). Tests in
  `test/update_test.dart`.

## No internet warning (2 Oct 2026, 0.1.50, released in v0.1.53)
- **What the user asked for:** "Add a check on opening to see if the internet is reachable. If it
  is not, pop up with a warning about some features not working and allow them to carry on using
  the application. If they try to use an online feature, check again for the internet and give
  the same warning again if nothing has changed."
- **The check** (`services/internet_check.dart`, `InternetCheck.reachable`): opens a plain
  connection (port 443, nothing sent) to the sites HomeTunes already uses: api.github.com,
  musicbrainz.org, lrclib.net, openlibrary.org. Any one answering within 4 s = online. No new
  site is contacted. About 80 ms on the user's PC when online. `InternetCheck.override` replaces
  it in tests; under `flutter test` the default is "online", so other tests never touch the
  network. `InternetCheck.last` keeps the latest answer.
- **At start-up** (main.dart, 1.2 s after the first screen): if offline, "No internet connection"
  lists what needs the internet (`onlineFeatures`: finding covers / song / book details online,
  finding lyrics online, searching online for video pictures and posters, checking for updates
  and What's new) and says music, audiobooks and videos still play, including from the home
  server. One button: **Carry on**. The "What's new" pop-up after an update waits until it's
  closed.
- **Before an online feature** (`ensureOnline(context)` in `ui/widgets/offline_warning.dart`):
  checks again every time. Online: carries straight on, no pop-up. Still offline: the same
  warning with **OK** (doesn't go ahead) and **Try anyway** (in case the check is wrong). Hooked
  into `showInfoLookup`, `showCoverSearch`, `showBookCoverSearch`, `showBookLookup`,
  `findLyricsOnline`, `showPictureSearch`, Settings › About's Check now / Try again, the Update
  button, and What's new in this version.
- **Not gated:** background lookups (automatic covers, details, lyrics, video art); they already
  fail quietly and try again later. The automatic update check is skipped when offline (0.1.51). The music server isn't checked
  (it's usually on the home network).
- **Tests:** `test/offline_warning_test.dart`.

## Search in filter drop-downs (2 Oct 2026, 0.1.49, released in v0.1.53)
- **What the user asked for:** "When filtering by something, the selection drop downs can get
  rather large, add a dedicated search bar at the top of each one."
- **How it works:** every "Show only" sheet (Your Library's Artists / Albums / Songs, Books,
  Videos' Collections and All videos) uses `SearchChoiceField` instead of a plain dropdown. It
  looks the same (label, current choice and its count, arrow). A tap opens a list under the field
  (above it when there's no room) with a **Search …** box first, then All and each choice with its
  count. Typing narrows the list: every word must appear, any order, ignoring case
  (`choiceMatches`); All only shows while the box is empty; "Nothing matches" when nothing does.
  Enter picks the first match; Esc or a tap outside closes it unchanged. On a PC the cursor is
  in the search box straight away; on a phone it waits for a tap so the keyboard doesn't cover
  the list.
- **Code:** `lib/ui/widgets/search_choice_field.dart`: `SearchChoiceField` (keeps the old
  `filter-<label>` keys), a `PopupRoute` on the root navigator laid out against the field's
  window position (`_Below`, max 400 px tall), and `_ChoiceList` (`choice-search-<label>` and
  `choice:<value>` / `choice:(all)` keys for tests). The choice rows keep the old
  "`Name  (count)`" text so existing tests still find them.
- **Tests:** `test/filter_search_test.dart`.

## Esc cancels a selection (2 Oct 2026, 0.1.48, released in v0.1.53)
- **What the user asked for:** "Make it so pressing escape on the PC cancels selection".
- **How it works:** while any selection bar is showing (songs, albums, audiobooks in the shell;
  collections, All videos, a collection's page and its in-place contents on Videos), Esc does the
  same as the bar's ✕. If two bars are up at once (Collections tab plus an open collection's
  contents), Esc clears both.
- **Code:** `lib/ui/widgets/escape_cancels.dart` (`EscapeCancels`) wraps each bar. It listens on
  `HardwareKeyboard` (so it works without focus) and only acts when its page is in front in its
  own navigator and every navigator above it (a dialog, menu or pushed page over it means Esc is
  left for that). It never marks Esc as handled, so the video player's Esc (leave full screen)
  still works even if a song selection is up in the shell behind it.
- **Tests:** `test/escape_select_test.dart`.

## Shift + click selects a range (2 Oct 2026, 0.1.47, released in v0.1.53)
- **What the user asked for:** "When using the select feature, I want to add holding shift to
  select everything between to points".
- **How it works:** while selecting, a click ticks or unticks one item as before and remembers it
  (the "anchor"). Holding Shift and clicking another item ticks everything between the anchor and
  that item, in the order shown on screen, either direction; the clicked item becomes the new
  anchor. A Shift + click also starts select mode straight away (it ticks that one item rather
  than opening or playing it), so Shift + click, Shift + click picks a range from scratch.
  Shift ranges only ever add ticks; a plain click still unticks one.
- **Where:** songs (`TrackTile`, the list it's in), albums and audiobooks (`SelectableCard`, its
  `scope`), and on Videos: collections (Collections tab, across category headings), the All
  videos grid and its Continue watching row, and episodes on a collection's page or its in-place
  contents (across seasons, in the flattened group order).
- **Code:** `lib/state/range_select.dart` holds `shiftHeld`, `idsBetween` and `RangePicker`
  (anchor + pick). `SelectionModel.pick(id, order, kind:)` uses it for songs/albums/books; the
  Videos screens keep their own `RangePicker` next to their `Set<String>` selections. Shift is
  read at tap time inside the `onTap` closure, never at build time. A range is only used when
  something is already ticked, so a stale anchor from an earlier selection can't fill a range.
- **Tests:** `test/shift_select_test.dart`.

## Servers page: several servers for music, audiobooks and videos (1 Oct 2026, 0.1.46, released in v0.1.53)
- **What the user asked for:** "We need to include a server connection system for videos, we also may
  want to have multiple server connections per server setup … re design this page … to allow for
  each section Music, Audiobooks and Videos to support connecting to multiple servers. (not all
  servers are created yet, so lets just set this up as a framework … It's also possible that a
  server may have content for all)". Asked first, the user chose **"Framework now"** (not "two
  Subsonic servers streaming side by side", which would change how server songs are stored: their
  ids are `server:<subsonic id>` with no server in them).
- **Server types** (`state/servers_model.dart`, `ServerType`): Subsonic (music, audiobooks; the
  only one that streams), Jellyfin, Plex, Emby (music, audiobooks, videos), Audiobookshelf
  (audiobooks), HomeTunes server (all three; our own, not built yet). Each has a label, a line
  about it, what it can hold (`can`) and an example address.
- **The list** (`ServersModel`, `servers.json`, backed up without passwords): `ServerEntry` (id,
  type, name, address, user name, what it's used for `uses` ⊆ `can`, the last test's result).
  Passwords go to the protected storage (`SecretStore.serverPasswordKey(url, user)`), never to the
  file; changing an address or user moves the password, removing a server deletes it, and nothing
  here ever touches the main server's own key. **The main music server** is still LibraryModel's
  (`server`, `serverEnabled`, `serverBooks`, connect / sync / forget / http consent all unchanged)
  and is shown in the list as entry `main` (name kept as `mainName` in servers.json). Its switches
  map to LibraryModel: Music → "Include server music", Audiobooks → "Audiobooks from the music
  server". A second Subsonic server is saved; **Make this the main music server** connects and
  syncs it (with the http consent if needed) and keeps the old one in the list with its password.
- **Test connection** (`services/server_probe.dart`, `probeServer`): for the types that can't stream
  yet it asks only the public "who are you" address, no sign-in sent (Jellyfin / Emby
  `/System/Info/Public`, saying which of the two it really is; Plex `/identity`; Audiobookshelf
  `/status` then `/ping`; HomeTunes `/api/info`, expecting `{"app": "hometunes", "version": …}`,
  which our server should answer). Addresses without a scheme try https then http. Subsonic is
  signed in to for real (`SubsonicClient.ping`) but never over plain http to the internet from a
  test (security review #4 still holds; making it the main server asks).
- **The page** (`ui/screens/settings/server_settings.dart`): "Add a server"; then **Music**,
  **Audiobooks** and **Videos** sections, each listing the servers that can hold that kind (a
  Jellyfin server shows in all three), a card per server (icon by type, name, "Type · address ·
  user", "Main music server" / "Coming later" tags, a status line, the last test, a switch "use it
  for this kind", ⋮ Edit… / Test connection / Sync now / Make this the main music server / Remove or
  Forget), and "Add a … server" (starts the dialog on the first type that holds that kind); last,
  **Kinds of server** (what works now, what's coming). The dialog: kind of server (coming-later
  ones marked), name (optional, defaults to the host), address (the plain-http warning), user name,
  password (eye; kept in protected storage), "Use it for" chips (kinds it can't hold greyed out; the
  main server always gives music), Test connection, Save / Connect. Adding a Subsonic server when
  there's no main one makes it the main one (connect + sync, as before).
- **Settings search**: `add-server`, `server` (Music servers; "navidrome" still finds it),
  `server-books` (Audiobook servers), `video-server` (Video servers); `book-server` (the old
  greyed-out Audiobookshelf preview) is gone.
- **Next, when a server type is built**: give it a client like `SubsonicClient`, ids that include
  the server (e.g. `jf:<serverId>:<itemId>`), and let LibraryModel / VideoLibraryModel take tracks
  and videos from every `ServerEntry` that `uses` that kind. For two Subsonic servers at once, server
  song ids need the server in them too (a one-time re-sync).
- **Tests:** `test/servers_test.dart` (saving without passwords, protected storage, sections, kinds
  a server can't hold, moving and deleting passwords, the main server in the list and its switches,
  test results kept, every probe with a fake http client including "no sign-in sent" and "never
  plain http to the internet", and the page: sections, adding a Jellyfin server from the Videos
  section). Also fixed a timing-dependent wait in `video_pictures_test.dart` (it waited a fixed
  100 ms for the online search; now until it's done, up to 5 s).

## Home revamp (1 Oct 2026, 0.1.45, released in v0.1.53)
- **What the user asked for:** "The home tab should include showing videos too. In fact, look over
  the content we have and revamp the home page." Asked first (1 Oct), the user chose: a mixed
  **Jump back in** row, then sections per kind; and **yes** to remembering recently played music.
  Asked in the same message for the Servers page (that's 0.1.46, see below / `04_…`).
- **Layout** (`ui/screens/home_screen.dart`), top to bottom: greeting; **Jump back in**; quick
  tiles (Shuffle all, Liked Songs, Favourite audiobooks, Favourite videos — the last three only
  when there are some — and up to six playlists); **Music** (Recently added, Your favourite albums,
  From your Liked Songs, Artists); **Audiobooks** (Recently added by newest file, Your favourite
  audiobooks); **Videos** (Up next, Recently added collections, Your favourite collections). Each
  section has a big heading with an icon, a thin accent line and **See all** (opens the tab), and
  is left out when there's nothing of that kind. Empty everywhere: "Nothing here yet" with **Add
  music** and **Add videos**.
- **Jump back in** (`ui/widgets/jump_back_in.dart`): videos part-watched (`continueWatching`, by
  the place's time), audiobooks part-listened (`ListeningModel.inProgress`, by the place's time)
  and recently played music (below), sorted newest first, 16 at most. Wide cards (320 wide; 88 high
  at the usual text size, taller with bigger text): picture (16:9 for a video, square otherwise),
  "Continue watching" / "Continue listening" / "Album" / "Playlist" / "Artist", the title, a line
  of detail (collection · episode, author · % done, artist, number of songs) and a progress bar
  for videos and books. The round play button carries on (video: opens its page, which resumes;
  book: `playBook`, which resumes) or plays the album / playlist / Liked Songs / artist again;
  tapping the card opens it the usual way (a video plays, the rest open their pages).
- **Recently played music** (`state/play_history.dart`, `history.json`, new): `PlayHistory`
  listens to the player; each time a new song starts playing (not an audiobook) it records where
  it was played from, from the queue's label: "Playlist · X" → the playlist (by name), "Artist ·
  X", "Liked Songs", anything else (an album, All songs, a search) → the song's album. Newest first,
  each place once, at most 50. Backed up (`AppBackup.dataFiles`; merging keeps both lists, newest
  first, `mergeHistory`) and re-read after a restore. **Settings › Playback › Forget recently
  played music** clears it (target `recently-played`).
- **Up next** (`upNextVideos`): for each collection you've watched something in (most recent
  first), its next episode (`nextUp`) when you've finished at least one and none is part-watched
  (that one is in Jump back in already).
- **Tests:** `test/home_test.dart` (labels → places, the history's order / limit / saving, backup
  merging, Jump back in's order on a real little library with a song, a book, a series and a film,
  Up next, the page's sections and See all, and the empty page). Not yet seen in a real window.

## Details for videos and collections (1 Oct 2026, 0.1.44, released as v0.1.44)
- **What the user asked for:** "Music and audio books allow for viewing the file details, I'd like
  this for the videos too".
- **Where:** **Details…** in a video's and a collection's right-click / hold menu, a **Details**
  button in the video player page's second row, and an ⓘ next to the heart on a collection's page.
  Opens on the root navigator, like the music one.
- **A video** (`ui/screens/video_details_screen.dart`, `VideoDetailsScreen`):
  - *Where it is:* folder (Show in folder, limited to the video folders), file name · format · size
    · changed date, and which video folder it was found in.
  - *Details and where they come from* (`services/video_details.dart`, `inspectVideo`, in the
    background): Title, Collection, Category, Season, Episode, Season title, Year, Genre,
    Description, Extra, Length, Picture size, Picture. Sources, checked in the scanner's order:
    your edit (with what the file says), the video's own .nfo, the series' tvshow.nfo, the file's
    tags (MP4 / M4V / MOV), the file name, the folder name (with which folder), "Read from the
    video" (length / picture size learned when its picture was made), "Taken from the video" (its
    automatic picture). A season title the user gave (`hasOwnSeasonTitle`) shows as an edit. New
    `DetailSource` values: `nfoFile`, `showNfo`, `fromVideo`, `frame`.
  - *What's inside the file* (`services/video_probe.dart`, `probeVideo`): the video engine opens
    the file in a hidden, paused player with `ao=null` and `sid=no` and reads `track-list` (JSON),
    `file-format`, `duration` and `chapter-list/count`, then closes it (about 0.5–0.7 s on the
    PC). Sound has to stay on: with no picture, sound or subtitle track chosen the engine closes
    the file at once and lists nothing (found with `tool/bench/video_probe_engine_test.dart`).
    Shown in plain words: format ("Matroska (MKV)"), length, overall bit rate (size ÷ length),
    chapters, and each picture / sound / subtitle track ("English · Dolby Digital (AC3) · 5.1 ·
    48 kHz · plays first", "Styled text (ASS)", "Pictures (Blu-ray)", forced, hard of hearing).
    Cover pictures stored in the file aren't listed as video. Only files inside the video folders
    are opened.
  - *What its .nfo file says*, *What the file's tags say*, *Files beside it that HomeTunes uses*
    (.nfo, tvshow.nfo, the collection's poster, subtitle files with their labels).
- **A collection** (`CollectionDetailsScreen`): its folders (first 8, then "and N more"), "N videos ·
  formats · size · length in all", its details (`collectionRows`: Name / Category / Year / Genre
  from the first video's sources when they match, else "Couldn't tell"; Description yours or the
  tvshow.nfo; Poster chosen, a picture in its folder, or the first video's picture), and every
  video as an opening row with its own details (and its tracks, asked for once opened).
- `details_screen.dart`'s cards and table are now public (`DetailsCard`, `DetailsLine`,
  `DetailsFolderLine` with `roots`, `DetailsPair`, `DetailsHeading`, `DetailsTable(rows:)`).
  `DetailsCard` is a Material now, so rows that open inside it (the album / book file list too)
  show their ripple.
- **Tests:** `test/video_details_test.dart` (sources on real files with .nfo files, a poster and a
  subtitle file; the engine's answer in plain words; both pages with a stand-in engine,
  `videoProbe`). The engine part was checked on a real MKV and MP4 with the bench test.

## Bottom bar and video volume linked again (1 Oct 2026, 0.1.43, released as v0.1.43; the user confirmed it works)
- **What the user reported (after v0.1.42):** the video player's volume bar was no longer linked to
  the bottom bar's, and the bottom bar only updated while a video played when its volume slider
  was pressed.
- **Cause:** the video page attaches its player to `NowWatching` (and says which video is showing)
  in `initState`, i.e. while the screen is being built. `NowWatching` told its listeners straight
  away, so the provider above the bar was marked for rebuilding in the middle of a build. In a
  test that's the "setState() or markNeedsBuild() called during build" error; in the release app
  the provider was left marked and never passed later changes on (play / pause, position, volume)
  until something rebuilt the bar directly. 0.1.42's loading page made it happen every time (the
  page now starts from a rebuild of its own).
- **Fix:** `NowWatching._notify` replaces `notifyListeners`: while a frame is being built
  (`SchedulerPhase.persistentCallbacks`) it waits for the end of that frame (one post-frame
  callback, merged), otherwise it tells listeners at once. Also covers detaching while a page is
  being disposed.
- **Tests:** `test/video_bar_link_test.dart` opens a page through `VideoPlayerScreen` (with
  `debugPage`) and checks the bar switches to the video and its volume follows the player's; it
  fails without the fix. `tool/bench/video_bar_engine_test.dart` confirmed the real engine
  reports playing, position and volume on its streams.
- Also in 0.1.43: `publish_release.ps1` only adds the "## What's new in …" heading when the
  notes file doesn't start with one (v0.1.41 and v0.1.42's pages showed it twice).

## Loading page while a video opens (1 Oct 2026, 0.1.42, released as v0.1.42)
- **What the user asked for:** "When loading a video, sometimes it can take a moment. Rather than
  looking like the application has frozen, lets show a loading page before the true page shows up".
- **How it works** (`video_player_screen.dart`). `VideoPlayerScreen` is now a small wrapper: it
  shows `VideoLoadingView` straight away (the video's title in the top bar, its picture dimmed at
  16:9 up to 480 px wide, a spinner, "Opening <title>…" and "collection · episode"; Back works).
  The real page (`_VideoPage`, which makes the player) only starts once the page's slide-in has
  finished (status listener on the route's animation, 400 ms at the latest), so the slide-in stays
  smooth. The page's first frame is drawn off screen with an animation that already reads as
  finished, so it waits to be *told* the slide-in finished rather than checking.
- **When the loading page goes:** the first time any of these happens (`_shown`): the video's first
  picture is drawn (`waitUntilFirstFrameRendered`, once per player), it's playing and the position
  moves, it can't be played (missing file or engine error, so the message shows), or 12 s pass.
  It then fades over 250 ms and is no longer built.
- **Next / previous video** (and Up next): the page stays; a dimmed spinner sits over the picture
  (`video-opening`) until that video is moving, or 12 s.
- **Tests:** `test/video_loading_test.dart` (with `VideoPlayerScreen.debugPage` standing in for the
  real page, which needs the video engine). The user tried it in the app and said it "works perfect".

## Copyable titles, video search, shrink to fit (1 Oct 2026, 0.1.41, branch `feature/titles-search-scaling`)
- **What the user asked for:** "titles of all medias should be highlightable to copy and paste";
  "the Search button on the left and tab should also search in video & collections"; "when
  scaling the window down, the widgets/buttons should scale down a little bit", as an option that
  can be turned off, in Appearance.
- **Titles** (`widgets/selectable_title.dart`). Each page's big title is a `SelectableTitle` (a
  `Text` in a `SelectionArea`, so "…" still works): album / artist / playlist header
  (`CollectionHeader`), the book page, Now Playing (song or chapter), a collection's page and its
  in-place contents, the video player page. The Details page already had one. Titles on cards and
  list rows stay tap-to-open (selecting there would fight the tap), so their menus got
  **Copy title** (`copyTitle`: clipboard + "Copied "…"" notice): songs (`track_tile.dart`),
  albums and books (`quick_actions.dart`, one at a time), videos (`showVideoMenu`) and collections
  (`showCollectionMenu`).
- **Search** (`search_screen.dart`): two more shelves after Audiobooks, **Video collections**
  (`searchCollections`: name, category, genre, year; tap opens the collection's page) and
  **Videos** (`searchVideos`: title, collection, genre, year; tap plays), 12 each, 220 px cards.
  Every word must match, as elsewhere. `VideoCard.onSelect` is now optional, so cards in Search
  have no "Select". Watches `VideoLibraryModel?` (absent in old tests).
- **Shrink to fit small windows** (`widgets/window_scale.dart`, `WindowScale` in
  `MaterialApp.builder`). On a computer, below 1200 × 760 the whole app is laid out as if the
  window were bigger and drawn smaller: 100 % at 1200 wide / 760 high, falling evenly to 80 % at
  760 / 520 and below (the smaller of the two). The MediaQuery size is divided by the factor, so
  the phone / desktop layout switch and every page see the bigger size. The bigger box
  (`OverflowBox`) sits outside the `Transform.scale`, not inside: the other way round, clicks in
  the right / bottom fifth of the window were thrown away as "outside" (caught by the test).
  Phones are left alone. **Settings › Appearance › Shrink to fit small windows** (`scaleWithWindow`,
  on by default, settings.json).
- **Tests:** `test/titles_search_scaling_test.dart`.

## The computer's sidebar (1 Oct 2026, 0.1.40)
- **What the user asked for:** "the left hand side bar can be scaled and hidden away by dragging
  or a click of a button", and two more entries like Liked Songs under Settings: one for
  audiobooks and one for videos.
- **Resize:** drag the sidebar's right edge (a resize cursor shows over it) between 180 and
  420 px. The drag is measured from where the mouse was pressed so the edge stays under it.
- **Fold:** the ☰ button at its top, a double-click on the edge, or dragging it narrower than
  130 px folds it to a 64 px strip of icons with tooltips (tabs, then Liked Songs, Favourite
  audiobooks, Favourite videos; playlists are hidden while folded). The same button, a
  double-click or a drag opens it again at the width it had. It animates (160 ms) except while
  dragging. Width and folded are saved in settings.json (`sidebarWidth`, `sidebarFolded`,
  `LibraryModel.setSidebar`), written when a drag ends, not on every move.
- **Favourite audiobooks** goes to the Audiobooks tab's first page with the Favourites chip on
  (other filters and the search cleared); **Favourite videos** goes to the Videos tab's
  Favourites sub-tab. Both use `AppNav.openView` / `takeView` (a one-off request the tab's first
  page picks up, like `openSettings`).
- **Code:** `ui/widgets/sidebar.dart` (`Sidebar`, moved out of `shell.dart`). Tests:
  `test/sidebar_test.dart`.

## Music videos (0.1.40, branch `feature/music-videos`, not released yet)

- **Which songs have one.** A song whose folder holds a video with the same name (`Song.m4a` + `Song.mp4`, any case; `.mp4`, `.m4v`, `.webm`, `.mkv` or `.mov`, `.mp4` preferred) gets it as its music video (`Track.video`). The video file is no longer listed as a second copy of the song. This is the layout the YouTube offline player writes (checked on `C:\Users\James.Miller\Videos\YouTubeOfflinePlayer`: 5 songs, 4 with videos).
- **An `.mp4` on its own** stays a song, as before (it plays as sound). If it has moving pictures (H.264, HEVC, VP8/9, AV1, MPEG-4; `mp4HasVideo` reads only the MP4 headers) it's also its own video. A sound-only `.mp4` has no video; still-picture tracks (audiobook chapter pictures) don't count.
- **Decided on every scan** (`local_scanner.dart` → `pairMusicVideos`), so a video added or removed beside an unchanged song is picked up by the next scan. Songs saved by older versions load with no video until the next scan. A previously scanned video file that is now paired disappears from the library like any removed file (kept as missing only if it has edits or playlist places).
- **Showing it.** Now Playing shows the video in place of the cover (wider, up to 16:9, capped at 960 px), muted, in a second player that decodes pictures only (`MusicVideoView`). The song still plays in the main player exactly as before (gapless, equaliser, ReplayGain, media keys). Play/pause follow the song; the video is moved back into step when it's more than 0.4 s out (seeks, skips, repeat-one, drift), then left alone for 2 s so it doesn't chase. Until the first picture arrives, or if the file can't be shown, the cover stays. A video shorter than the song stays on its last picture. With lyrics open on a phone, the lyrics replace it as they replace the cover. Books never show videos.
- **Enlarge and full screen (music videos).** Buttons in the video's bottom-right corner (shown while the mouse is over it, or after a tap; they fade after 3 s): **Enlarge** makes the video fill the middle of Now Playing (the lyrics panel steps aside; remembered for the session) and **Full screen** fills the monitor (or the phone). In full screen the song's title, previous / play-pause / next and a "leave full screen" button show when the mouse moves; Esc or F leaves, Space plays or pauses the song, double-click switches full screen on and off. If the next song has no video while in full screen, full screen closes by itself. `MusicVideoControls` in `music_video_view.dart`.
- **Settings › Music** (its own page since 30 Sep, user's request): **Show music videos** (`showMusicVideos`, on; off = always the cover and no video button) and **Play music videos automatically** (`autoPlayMusicVideos`, on; off = the cover shows first and the video button starts the video). The video button beside Lyrics on Now Playing switches between video and cover **for the song playing only** (it no longer changes the saved setting). Moved out of Settings › Playback, which keeps how songs sound.
- **The engine.** Needed libmpv's video build (`media_kit_libs_video` instead of `media_kit_libs_audio`, plus `media_kit_video`). The main player keeps `vid=no` so it never decodes pictures. Windows `libmpv-2.dll` goes from 14.8 MB to 28.4 MB; the APK grows too. Real-engine check: `tool/bench/video_engine_test.dart` (4K VP9 opens, seeks in ~0.1 s, stayed within 0.07 s of the song over 8 s). The audio-only engine had no video decoders at all, which is why the videos couldn't have been shown before.

## Videos tab (0.1.40, branch `feature/music-videos`, not released yet)

- **Folders.** Settings › Folders & scanning › **Video folders** (`LibraryModel.videoFolders` in settings.json, with Add, Rescan videos, the count and any scan problem; `VideoFoldersSection`). They're scanned by `VideoLibraryModel`, separately from the music scan: adding a folder scans it, removing one drops its videos at once, and a folder that can't be reached keeps its videos. An `.mp4` on its own inside a video folder is a video, not a song (`_isVideoFolderFile` in `LibraryModel._rebuild`); a song's music video beside it is unaffected.
- **Formats.** `.mp4 .m4v .mkv .webm .mov .avi .wmv .flv .mpg .mpeg .m2ts .mts .ts .3gp .ogv .vob .divx .asf` (`videoFileExtensions`). The engine (libmpv/FFmpeg, video build) plays practically all of them.
- **Details.** An `.nfo` beside the video wins (see below); then MP4/M4V/MOV tags; then the folders and file name (`video_names.dart`, `describeVideoPath`). Category folders (`TV`, `Anime`, `Films`, `Movies`, `Clips`, `Videos`…) become the **category**, and the folder under them the **collection**, cleaned up (`Silo - S1-3 [1080p]` → "Silo", `Mickey.17.2025.2160p.WEBRip` → "Mickey 17", 2025). Season folders (`Season 1`, `S01`, `Specials` = season 0), extras folders (`Extras`, `Featurettes`, `NCOP`…) and named parts (`Alicization`) are understood; episodes from `S01E02`, `1x02`, `Episode 2`, `Ep. 2`, `- 02`, a leading `02 Title` or a trailing number, with the collection name taken off the title. A folder whose first sub-folders are seasons is itself the collection; loose files in a video folder take that folder's name. On F:\Videos (1604 files) this gives about 39 collections. `dart run tool/probe_video_names.dart <folder> [n]` shows the result for any folder. Unchanged files are reused on rescan (thumbnail, length and "added" date kept); `videoScanVersion` (now 5) makes older entries be read once more.
- **Season titles** (30 Sep). A season folder's text after its number is the season's title: `Season 1 - Offline News` → "Offline News", `Book Two - Earth` → "Earth" (`seasonTitleOfFolder`; a year, release details or "Episodes 1-10" don't count). A series' `tvshow.nfo` `<namedseason number="1">` wins over the folder. Headings, contents chips and the All videos › Season sort show "Season 1 – Offline News". The ✎ on a season's heading (collection page and in-place contents) gives it its own title ("Use the folder's title", or empty for none): saved in videos.json `seasonTitles` (by collection key and season number, "" = none on purpose; follows a rename; in backups) and, with the .nfo box ticked, as `<namedseason>` in tvshow.nfo (`namedSeasonKey`; that one season's tag only, others kept). `VideoItem.seasonTitle` holds what the files say; `VideoLibraryModel.seasonTitleOf` / `groupLabel` add the user's own. A video whose season is changed by an edit drops the old title.
- **Season sub numbers** (30 Sep, user's request: "season 1.1"). A folder `Season 1.2`, `S01.2` or `Season 1.2 - Outside` gives season 1, sub number 2 (`subSeasonOfFolder`; `S01.1080p` doesn't count, and an episode numbered for another season doesn't take it). `VideoItem.subSeason` / `seasonLabel` ("1.2"); labels read "S1.2 E3", headings "Season 1.2 – Outside", and a collection lists Season 1, 1.1, 1.2, then 2 (`sortForCollection`). Edit details' Season box takes "1.2" (and "1" takes the sub number away; for several videos a typed season applies to all, sub number included); saved as `VideoEdit.subSeason` / cleared `subSeason`. A sub season can have its own title (✎, stored under "1.2" in `seasonTitles`), but it isn't written to tvshow.nfo, which only knows whole seasons, and a sub season's title comes from its folder rather than `<namedseason>`. The episode .nfo keeps writing the whole season number. `videoScanVersion` 5.
- **Collections (like albums).** `VideoCollection`, built by `VideoLibraryModel._rebuild` from the videos' collection names (any case): its category, earliest year, most common genre, poster (`poster.jpg`, `folder.jpg`, `cover.jpg`, `season-all-poster.jpg`, `show.jpg`, `movie.jpg` in its folder, else the first thumbnail), a description, and its videos in watching order (seasons, then parts in folder order, then specials, then extras; by episode, then title). Favourite collections, collection descriptions and the audio/subtitle choice per collection are saved in videos.json and follow a rename.
- **Sub-tabs.** **Collections** (grid of `CollectionCard`s with poster, category · count · year and "n of m watched"; sorts: Category (headed, "Other" last, default), Name, Recently added, Recently watched, Most videos, Year; filters: Category, Genre, Decade), **All videos** (the grid described below) and **Favourites** (favourite collections). ⋮ / right-click on a collection: Open collection page, Play / Continue, Add to / Remove from favourites, Edit collection…, Change poster…, Mark all as watched, Select. A video's menu has "Go to collection". **Tapping a collection card doesn't open a new page** (like albums on an artist page): its contents open in a panel under its row (`CollectionContentsPanel`: name and details, Play / Continue, Open collection page, ⋮, ✕; seasons with fold-up headings, only the one with the next episode open to start with); the card gets an outline; tapping it again or ✕ closes it, and a panel opened low down scrolls up into view. Hovering a collection's picture (card or page header) shows a round play button, like album covers (`HoverPlayCover`), which plays or carries on with the next episode. **Select mode** (right-click › Select, or press and hold): tap more cards; the bar has Select all, Edit collection / Edit n collections (`showEditCollections`: for several, category, year, genre and poster shape, only what's typed or picked, saved on every video; the .nfo tick box too), Change poster (one), favourite, Mark all as (not) watched.
- **A collection's page** (`video_collection_screen.dart`): poster, name, category, "4 videos · 1 extra · 4 h 21 min · 0 watched", **Continue S1 E2** / Play, heart, Edit collection, Mark all as watched, then the videos under Season / Part / Specials / Extras headings, the one to watch next highlighted. Tapping a heading folds that season up or opens it (the heading shows "3 of 8 watched" and a ▶ on the season with the next episode). With two or more headings a **contents bar** stays pinned under the header: a chip per season (▶ on the one with the next episode, ✓ on fully watched ones) jumps there, opening it if folded, plus **Fold all / Open all**. Rows and headings have fixed heights (`rowExtent` 98, `headingExtent` 52) so the jump can be worked out without building every row; folding is for this visit only. **Selecting episodes** (30 Sep): right-click / press and hold an episode › Select, on the page or in the in-place contents; then a tap ticks, each season heading gets a box for the whole season (partly ticked shows –), and the shared `VideoSelectionBar` (also used by All videos) offers Select all, **Edit details** (one) / **Edit n videos** (several, the usual Edit details dialog), Mark as watched / not watched (`_EpisodeSelection` mixin). **Season heading menu** (30 Sep): right-click / press and hold a season heading (page and in-place contents) for **Select all in Season n (count)** (starts select mode with the whole season ticked, or adds it to what's ticked), Unselect Season n (when any of it is ticked; replaces Select all once it's all ticked), Mark as watched / not watched, Season title… (numbered seasons) and Fold up / Open (`showVideoGroupMenu` in `videos_screen.dart`, `_EpisodeSelection.headingMenu`).
- **Edit collection.** Name (another collection's name joins the two), Category (with a list), Year, Genre, Description. Name, category, year and genre are saved as an edit on every video in it (`editCollection`); the description is the collection's own. Edit details (one video) also has Season (0 = specials) and Episode; several videos can be given a season together.
- **.nfo files** (`video_nfo.dart`, `widgets/save_nfo.dart`). The video files themselves (mostly multi-GB MKVs) are never rewritten; instead, with **"Also save into .nfo files beside the videos"** ticked (in Edit details and Edit collection, remembered, on by default, not shown on Android), the edited details are written Kodi / Jellyfin / Plex style: `<video name>.nfo` beside each video (`<episodedetails>` with title, showtitle, season, episode, year, genre, plot for a series; `<movie>` with title, set, year, genre, plot otherwise) and `tvshow.nfo` in a series' own folder (never in a category folder or a mixed video folder). An existing .nfo keeps everything HomeTunes doesn't manage (ids, actors, comments); only those tags are replaced; files are written beside themselves then swapped in; only files inside the video folders are touched. A snackbar says how many were written. The scanner reads them back (and any made by other programs, re-reading a video when its .nfo changes), so the details survive a new install. Category has no .nfo tag and stays a HomeTunes edit.
- **Thumbnails.** Made in the background after a scan by one hidden, silent player (`VideoThumbnailer`): a frame a tenth of the way in (at most 1 minute), shrunk with Flutter's decoder and saved as a ~30 KB JPEG in `art/video/` (named by path + modified time). It also learns the real length and picture size. About a second each for 4K. Unused ones are tidied away.
- **Choosing pictures and posters** (`video_pictures.dart`). **Change picture…** (a video's menu, and its player page) and **Change poster…** (a collection's menu, and "Change poster" on its page) offer: **Choose an image file…**; **Pick a frame…** (a small silent player with a scrub bar, ±10 s and one-frame-back / forward buttons, `hr-seek` for the exact frame; for a poster, a frame of the collection's next video); **Search online…**; and **Use the automatic picture** once one is chosen. The player page also has **Use this frame as its picture** (a screenshot of the frame on screen, without subtitles). Chosen pictures are shrunk to at most 1280 px wide (never enlarged), kept in `art/video/custom/` named by their contents, saved in videos.json (`pictures` by video id, `posters` by collection key; a rename keeps the poster), included in backups (the `custom` folder always goes in) and tidied away when no longer used. `thumbFile` / `coverFile` prefer them. Collection pictures are drawn whole over a blurred copy of themselves (`PosterPicture`), so a tall poster isn't cut to its middle in the 16:9 cards.
- **Search online** (`video_art_search.dart`): three free services with no account or key, asked at once: **TVmaze** (TV: the best two shows' posters, backgrounds and banners, and that episode's still when searching for one video; CC BY-SA, credited in the dialog), **AniList** (anime covers and banners; asked first for an Anime category) and **Wikipedia** (the article's infobox picture, which for a film is usually its small "fair use" poster, else its free picture; "film" / "TV series" / "anime" is added to the search by category so "Claymore" doesn't find swords). Results show posters first for a collection and wide pictures first for a video; a service that fails is named and the others still show. Only the typed name (and season / episode) is sent, only on searching. Settings › Online lookups › **Find video pictures online** (`onlineVideoArt`, on by default) turns the option off. TMDB / fanart.tv were left out because they need a personal API key. `dart run tool/probe_video_art.dart "Silo" 1 2` asks the real services.
- **All videos.** A grid of thumbnails with length badges, a progress bar and a watched tick; chips for All / Continue watching / Not watched / Watched (with counts); a **Continue watching** row across the top of All; search (title, collection, genre, year); sorts: Collection (default, headed groups), **Season** (each collection's seasons in watching order under "Silo · Season 1 – Offline News" headings; a collection without seasons gets just its name), Title, Recently added, Recently watched, Year (headed), Longest. Right-click / press and hold / ⋮: Play, Play from the start, Edit details…, Mark as (not) watched, Show in folder (Windows), Select. In select mode the top bar has Select all, Edit details, Mark as watched / not watched. Right-click / press and hold a group heading (any headed sort; with Season sort, one season of one collection) for the same heading menu as a collection's seasons: Select all in it, Unselect it, Mark as watched / not watched.
- **Filters.** The filter button (a dot on it while filters are on) opens the same "Show only" sheet as the Library tabs: Collection, Genre, Decade, Length (Under 10 minutes … Over 2 hours, shortest first), Picture (4K, 1440p, 1080p, 720p, SD, by the shorter side so upright phone videos count right) and File type. Each list shows counts and is narrowed by the other picks. Filters in use show as chips beside the watched chips (tap to change, × to remove, "Clear filters" for several); the chip counts and search work within them, and the Continue watching row hides while filtering. Length and picture are only known once a thumbnail has been made (or the video has played). `videoFilterFields` / `filterVideos` in `video_filters.dart`; `FilterField` gained an optional `order` for lists that shouldn't be A–Z.
- **Editing.** `edit_video.dart`: Title, Collection (with a list of existing ones), Year, Genre, Season, Episode, Description. Saved as edits in videos.json and laid over the file's details (and optionally into .nfo files, above). One video: any box can be changed or emptied, and "Undo my changes" goes back to the file. Several: boxes that differ start empty with `--:--`, only typed boxes are applied, and titles can't be set together.
- **Playing.** `video_player_screen.dart`, opened inside the Videos tab: media_kit's standard controls (seek bar, play/pause, volume, full screen; on a computer Space, arrows, F and Esc work too), then the details and buttons for **Enlarge** (the video fills the whole page; a button in its corner shrinks it again), **Full screen**, Edit details, Mark as watched and Show in folder. Under the details the buttons are in two rows (30 Sep, user's request): the main ones (Enlarge, Full screen, Audio and subtitles, Speed; tonal, highlighted) and below them the others (Equaliser, Edit details, Use this frame, Change picture, Mark as watched, Show in folder; outlined). It carries on from the saved place ("Carrying on from 12:34" with Start over), unless it was near the end. The place is saved every 5 s, on pause and when the page closes; the last 5 % or last 20 s counts as watched. Starting a video (or carrying on with it after a pause) pauses the music or audiobook; starting music pauses the video. Media keys control whichever was started last (below). **Previous / next video** (30 Sep, user's request): ⏮ and ⏭ either side of the skip buttons in the player's bar (normal and full screen, computer and phone) and in the bottom bar, greyed out at either end of the collection (`VideoLibraryModel.before` / `after`; next never runs from the last episode into the extras); Shift+P / Shift+N and the keyboard's previous / next track keys too; the place in the current video is saved first.
- **The video in the bottom bar and on the media keys** (30 Sep, user's request). While a video page is open and its video was the last thing started, the bottom player bar (computer) / mini player (phone) shows the video instead of the music: its picture, title and "Silo · S1 E2" (tap, or the ▶-screen button, to go back to its page on the Videos tab), skip back / play-pause / skip forward (Settings › Videos amounts), its progress bar and its volume (`VideoPlayerBar`, `VideoMiniPlayer` in `widgets/video_now_playing.dart`). The system media controls (keyboard play/pause key, Windows media overlay, phone notification) show and control it the same way; next / previous go to the next / previous video in the collection, or skip by seconds when there isn't one. Music that starts playing takes the bar and keys back; closing the page gives them back too. `NowWatching` (`state/now_watching.dart`) holds the page's player (through `VideoTransport` / `MediaKitTransport`), made in `main.dart` and given to `MediaSession`. 1 Oct (user: link the two volume bars; the bar sometimes didn't update): the bar follows the player's volume however it's changed (the player's own volume bar, its wheel, the bottom bar), and when a second video page closes the bar goes back to the page still open underneath instead of dropping the video. **Fix (1 Oct, user's bug: "Go to the video" sometimes led to a blank Videos tab until restart):** `_bringBack` called `AppNav.selectTab`, which on the tab already showing goes back to its first page (closing the video page), then `popUntil(r == route)` never found the page and popped the tab's first page too. Now it uses `AppNav.showTab` (switch only, never pops), pops only while the page is still in the stack (`route.isActive`), and stops at the first page (`r.isFirst`). Test: `test/go_to_video_test.dart`. **Fix (1 Oct, user: the bar didn't always switch from music to video until the slider was pressed):** the switch relied on the video's single "playing" event arriving in the right order. `NowWatching._check` now looks at the players as they are whenever the video's position moves or the music stops: video playing and music not → the video is in front; a play / pause the bar hasn't shown yet → redraw. It only tells the bar when something changed. `play()` from the bar tells the bar at once.
- **Scroll to skip** (30 Sep, user's request). With the mouse over a progress bar, a wheel notch up skips forward 5 s and down goes back 5 s (quick notches add up); only over the bar, so the page still scrolls elsewhere. On the music / book bar (desktop bar and Now Playing, `WheelSeek` in `widgets/wheel_seek.dart`), the video's own bar in the bottom bar, and media_kit's progress bar over the video, normal and full screen (`VideoWheel`: it wraps the controls and works out where media_kit draws the bar, `videoSeekBarBand`; the wheel anywhere else on the video still changes the volume by 5, which media_kit used to do itself and now doesn't, `modifyVolumeOnScroll: false`).
- **The player's buttons: Settings › Appearance › Video player** (30 Sep; `VideoPlayerLook` in `models/video_player_look.dart`, saved as settings.json `videoPlayerLook`; applied by `widgets/video_controls_look.dart`). **Button colour** (White default, Theme highlight, Black, or your own via the colour picker), **Button size** (Small 22 / Normal 28 / Large 36 px; phone 20/24/32; the bar gets taller for Large), **Behind the buttons** (None, **Soft glow** default: a blurred halo plus an icon shadow; **Circles**: a disc / pill behind each button and the time) with a **Strength** slider (20–90 %, default 55 %), and **Progress bar colour** (Theme highlight default, Red, White, own; the unplayed part and the volume bar follow the button colour, faded). The backing is always the opposite shade to the buttons (dark behind light, light behind dark), which is the fix for buttons disappearing into a black (or white) scene. On a phone the dimming behind the controls follows the strength. A live preview over a Dark / Bright / Busy made-up scene shows the choice. Both the normal and full-screen control themes get it (full screen is its own route). Reset button puts it back.
- **Audio and subtitles.** Many MKVs carry several audio tracks (Claymore: English and Japanese) and subtitle tracks (text, ASS "Full / Signs & Songs", DVD picture subtitles). A subtitles button in the player's bottom bar (normal and full screen, computer and phone) and **Audio and subtitles** on the page open a chooser: every audio track plus **Off (no sound)**, every subtitle track plus **Off**, labelled by language name, title and codec (`trackLabel`). Subtitle files beside the video (`Name.srt`, `Name.en.srt`, `Subs/Name/2_English.srt`, `Subs/Name*.srt`; `.srt .ass .ssa .vtt .sub .idx .sup`) are added as "English (file)" choices with mpv's `sub-add`. The choice is remembered **per collection** by language and title (`TrackPick`, `matchTrack`), so the next episode picks the same ones even when track numbers differ. On Windows mpv draws the subtitles itself (`PlayerConfiguration(libass: true)`), which is needed for styled ASS and picture subtitles; on Android media_kit's Flutter subtitle view is used (text subtitles only). The page's details line shows the current choice.
- **Settings › Videos** (`video_settings.dart`, 0.1.40), like Settings › Audiobooks. *Watching:* **Skip back / Skip forward** (5–60 s, default 10 / 10: the player's skip buttons in the bottom bar, normal and full screen, the ← → and J / L keys, and a double-tap on the left / right of the picture on a phone; the keyboard map is media_kit's with those keys changed, plus K for play/pause), **Speed** (the usual speed; changing it while watching, with the speed button in the bar or "Speed 1×" on the page, is remembered **per collection** in videos.json `speeds`), **Rewind a little when carrying on** (on; `PlayerModel.resumeRewind`, as for books), **Separate equaliser for videos** (on; `EqualizerModel.separateVideos` / `videoPresetId`, default Flat; the Equaliser screen gets a Videos segment, `EqTarget`, and opens on it from the player page's Equaliser button). The video player gets the bands as its `af` filter and the overall level as mpv's `replaygain-fallback` (a `volume` filter inside the lavfi graph stalled playback on this engine, and it has no `volume-gain`), so its volume slider stays the listener's. *Where your videos are:* the video folders (same list as Folders & scanning) and "Also save edits into .nfo files". *Look:* the usual **Video picture shape** and **Collection poster shape**: Wide (16:9), Tall (2:3) or Square.
- **Picture shapes.** Each video (Edit details, one or several: "Usual (wide) / Wide / Tall / Square") and each collection (Edit collection › Poster shape) can have its own; kept in videos.json (`shapes`, `collectionShapes`; a rename keeps it; in backups). Cards take the shape; the grids are laid out in rows (`sliverCardRows`), each row as tall as its tallest card, so mixed shapes line up. A collection's picture is drawn whole over a blurred copy (`PosterPicture`); a video's thumbnail fills its shape (cropped).
- **Up next.** At the end of a video the next one in its collection (`after`, never running into extras) starts after a 10 s countdown (Cancel / Play now).
- **Saved in** `videos.json` (`VideoLibraryModel`): the scanned videos, the edits, the places, favourite collections, collection descriptions, the track choices, chosen pictures and posters, picture shapes, speeds per collection, the user's season titles, and whether to save .nfo files. Included in backups (a merge keeps this device's scan, adds the backup's edits and keeps the newer place per video; a thumbnail path outside `art/` is dropped). The video folders restore like music and audiobook folders.
- **Android.** Video files need "Photos and videos" (`READ_MEDIA_VIDEO`, added to the manifest and `patch_platforms.dart`), asked for when a video folder is added. Music videos on the phone need it too: Settings › Music shows "Allow" under the music video switches when it's missing (`MusicPermission.checkVideos` / `requestVideos`).
- **Not done yet:** videos in Search and on Home; a video plays only while its page is open (switching tab keeps it going; going back from the page stops it); details aren't written inside the video files themselves (only .nfo files); styled / picture subtitles on Android.

## Colour themes (0.1.24)
- **The user's choices (29 Sep):** the original look stays as **Default**; two more dark themes,
  **Midnight** (navy, sky-blue accent) and **Forest** (dark green-grey, green accent); and **Your
  own** = a highlight + a background colour, with panels and grey text worked out from those.
  The choice goes into backups (settings.json: `theme`, `customAccent`, `customBackground` as
  `#RRGGBB`; a *merge* restore keeps this device's theme, like other settings).
- **Where:** the **Settings › Appearance** page (`appearance_settings.dart`) with a preview card
  per theme and a colour picker (suggested swatches + Shade / Strength / Brightness sliders, and a
  colour code box since 0.1.29).
  Backgrounds are held at HSL lightness ≤ 0.2 and highlights 0.45–0.8, so white text stays
  readable (`AppPalette.keepDark` / `keepVisible`).
- **How it works:** `ui/theme.dart` has `AppPalette`, `builtInPalettes`, `paletteFor`, and
  `AppColors` is **getters** reading `AppColors.current` (they used to be `static const`).
  HomeTunesApp (main.dart) wraps MaterialApp in a `Selector<LibraryModel, AppLook>`
  (`lookOfSettings`, since 0.1.25: palette, corners, text size), sets `AppColors.current`, builds
  `buildTheme(palette)`, and `RedrawOnThemeChange` (in `appearance_settings.dart`) marks every
  element to build again after a change (widgets that read AppColors directly wouldn't notice
  otherwise).
- **Rule for new code:** never put `AppColors.x` in a `const`, a `static final` or a top-level
  `final`; read it in `build`. The compiler catches the `const` case.
- **Tests:** `test/theme_test.dart`. Pictures of each theme without showing anything on screen:
  `flutter test tool/theme_preview_test.dart` writes PNGs to `C:\Temp\ht\preview` (or the folder
  given with `--dart-define=OUT=...`).
- **Don't take screenshots of the user's desktop or launch the app on their screen** to check the
  look: on 29 Sep that captured a game the user was playing. Use the off-screen preview instead.

## Folder options and mute (0.1.27)
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
  - **Video folders** (30 Sep, 0.1.40, user's request: "the same setting options as the music and
    audiobook folders"): each video folder row (Folders & scanning and Settings › Videos, the
    shared `VideoFoldersSection`) has the same button (`FolderOptionsButton(videos: true)`). Rescan
    this folder → `VideoLibraryModel.scanFolder` (queued with other video scans; replaces only the
    videos inside it, then makes thumbnails). File types come from the scanned videos
    (`VideoLibraryModel.formatsIn`, "3 videos") and are stored in the same `hiddenFormats` map;
    `VideoLibraryModel._rebuild` leaves those videos out of `videos` and the collections at once,
    keeping their places and edits, and notices a change through `_hiddenKey`. Removing a video
    folder forgets its choices. Tests: `test/video_folder_options_test.dart`.
  - Audiobook folders got both options (the user asked for the rescan; file types came with
    the same window).
- **Mute:** the speaker icon beside every volume slider (`VolumeControl`: player bar, Now
  Playing, the mini player's pop-up) is a button: `PlayerModel.toggleMute` goes to 0 and
  remembers the volume; clicking again puts it back (to 50% if it was dragged to 0 by hand).
  The icon is in the highlight colour while muted.
- **Tests:** `test/folder_options_test.dart` (real scans of the sample files). Picture:
  `tool/ui_preview_test.dart` → `ui-folder-options.png`.

## Queue drawer, artist albums in place, Settings order (0.1.26)
- **The user's choices:** the queue is a **drawer from the side on the phone too**; the tab is
  called **Folders & scanning**; the audiobook folders are shown **in both places** (the same
  setting).
- **Queue:** `openQueue` → `openQueueDrawer` (`queue_screen.dart`): a `showGeneralDialog` on the
  root navigator sliding in from the right, `QueuePanel` (min(420 px, 88% of the window)) with
  a title and ✕, `QueueList` inside (drag the handle to reorder, swipe left to remove, tap to
  jump). Closes on a tap outside, Esc, ✕ or a quick swipe right. There's no full-page queue
  screen any more.
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

## Advanced appearance (0.1.25)
- **What the user sees:** Settings › Appearance › **Advanced**:
  - Saved themes: **New theme from the current one**, **New light theme** (starts from
    `lightStarter` "Daylight"), and Edit… / Duplicate… / Delete on each. Saved themes also appear
    as cards beside Default / Midnight / Forest / Your own.
  - The **theme editor** (`ThemeEditor`): name, a live preview, and eight colours with plain
    names (Background, Panels, Raised panels, Text, Grey text, Highlight, Slider track, Play
    button). The picker's "any" mode allows every colour. Warnings (`readabilityProblems`, the
    usual 4.5 / 3 contrast rules) say in plain words what may be hard to read; saving is still
    allowed. **Save and use** switches to it straight away.
  - **Deleting:** each saved-theme row has visible Edit and Delete buttons
    (plus ⋮ with Duplicate), and the editor has **Delete this theme** for themes already saved.
    All go through `confirmDeleteTheme` (asks first; says so when the theme is in use, which
    goes back to Default).
  - **Reset to default colours** under "Your own colours": clears
    `customAccent` / `customBackground` (`LibraryModel.resetCustomColours`), stays on "Your own",
    and shows a notice with **Undo** (`restoreCustomColours`). Greyed out when nothing was chosen.
  - **Text size** (Smaller 0.9 / Default / Larger 1.15 / Largest 1.3, on top of the system
    setting, via `withTextSize` in MaterialApp.builder) and **Corners** (Square / Slight / Default
    / Extra round → `AppShape.scale` 0 / 0.5 / 1 / 1.6, plus Material's cards, dialogs, buttons,
    menus and sheets in `buildTheme`).
- **Saved in settings.json** (so in backups): `savedThemes` (list of `{id: "saved:…", name,
  background, panels, raisedPanels, text, greyText, accent, sliderTrack, playButton}` as
  `#RRGGBB`), `textSize`, `cornerRoundness` (clamped on load to 0.8–1.5 and 0–2). `LibraryModel.saveTheme /
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
- **Tests:** `test/theme_test.dart`. In widget tests, don't `await`
  LibraryModel saves: Storage writes one file at a time and a write started inside the test's
  pretend clock never finishes, so a second awaited save hangs. The screen updates before the
  save anyway.
- **Pictures:** `flutter test tool/theme_preview_test.dart` now also draws a saved light theme with
  square corners and larger text, and the theme editor (`theme-light.png`, `theme-editor.png`).

## Updates (0.1.23)
- **The user's choices (29 Sep):** a "Check for updates" button in Settings › About **plus** a quiet
  check at most once a day with a switch to turn it off (**changed 2 Oct, 0.1.51:** the quiet
  check now runs every time HomeTunes opens, if online; see "Update check at start-up"); on the phone, just **open the download
  page** (not download-and-install); on Windows it updates itself.
- **Where things are:** `services/update_checker.dart` (GitHub, versions, checksums, installer),
  `state/update_model.dart` (`UpdateModel`, `updates.json`: `autoCheck` + `lastCheck`; not in
  backups, it's per device), `ui/screens/settings/update_ui.dart` (About rows, the question
  dialog, the start-up notice). `main.dart` runs `checkAtStart()` after the internet check at every start (was `checkIfDue()` 8 s after start, at most daily, until 0.1.51); a find shows a
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
- **Publishing:** copies from 0.1.23 on update themselves only if the release is published with
  `tool/publish_release.ps1` (the asset names and the SHA256SUMS file are what the app looks for).
  Copies older than 0.1.23 have no updater and must be updated by hand once.
- **Tests:** `test/update_test.dart` (fake GitHub). Live check: `flutter test
  tool/probe_update_test.dart` reads the real latest release, downloads its installer and checks
  the checksum (nothing is installed).

## Licence (0.1.31)
- **The user's choice (30 Sep):** **MIT**, like Nora, copyright **"Copyright (c) 2026
  Jamesking96"** (their GitHub name). Compared first: Harmonoid uses PolyForm Strict (personal,
  non-commercial use only; no changes or redistribution); Nora uses MIT.
- **Why MIT is allowed:** every Dart package is MIT or BSD (checked 30 Sep). The bundled audio
  engine (libmpv + FFmpeg n6.0 from media-kit's prebuilt "audio" builds) is **LGPL-3.0-or-later**:
  the binaries themselves say `-Dgpl=false`, `--disable-gpl --enable-version3`, "libavcodec
  license: LGPL version 3 or later" (Windows `libmpv-2.dll`: mpv v0.36.0-403-g652a1dd907,
  release 2023-09-24; Android `libmpv.so`: mpv 0.35.1, v1.1.8). LGPL is fine with MIT as long as
  it stays a separate replaceable library and its notice + LGPL + GPL texts ship with the app.
  **Never add a GPL library, or swap in a GPL libmpv build (e.g. the "video" builds with GPL
  parts), without revisiting this.**
- **Files:** `LICENSE` (standard MIT text so GitHub detects it), `THIRD_PARTY_NOTICES.md`
  (engine versions, source links, replaceability; vendored packages; pub packages with
  licences; VC++ runtime; online services), `licenses/LGPL-3.0.txt` + `GPL-3.0.txt` (official
  GNU copies; SHA-256 with LF line endings: LGPL e3a994d8…, GPL 3972dc97…; a CRLF copy hashes
  differently). They're bundled as assets in `pubspec.yaml`.
- **In the app:** Settings › About › **Licences** → Flutter's `showLicensePage` (lists every
  package, including HomeTunes' own LICENSE, plus the engine). `services/app_licences.dart`
  `registerAppLicences()` (called in `main`) adds the libmpv/FFmpeg notice with the LGPL text,
  and the GPL text, from the bundled assets.
- **Downloads:** `tool/build_release.ps1` copies `LICENSE.txt`, `THIRD_PARTY_NOTICES.md` and
  `licenses\` next to `hometunes.exe`, so the zip and installer both have them. The installer
  shows Jamesking96 as publisher, with the GitHub links and copyright line. The APK carries them
  in its assets and the Licences page.
- **Engine source on every release (the user's choice, 30 Sep):** `tool/engine_source.ps1` makes
  `build\dist\HomeTunes-audio-engine-source.zip` (17.5 MB): mpv at commit 652a1dd9 (Windows) and
  v0.35.1 (Android), FFmpeg 6.0 (official tarball, matches ffmpeg.org's checksum), GNU FriBidi
  1.0.13 (LGPL-2.1+, only in the Windows dll), and snapshots of both media-kit build repos
  (win32 master at f5a6f879, the last commit before its 2023-09-24 build; android v1.1.8), with
  a README listing sources and SHA-256s. Versions were read from the binaries themselves (the
  win32 build scripts don't pin versions). `publish_release.ps1` adds the zip to every new
  release (and its checksum); `tool/attach_engine_source.ps1` added it to all older releases
  on 30 Sep. Permissive libraries inside (mbedtls, libxml2, libass, HarfBuzz, FreeType, zlib…)
  don't need their source shipped.
- **When dependencies change:** update `THIRD_PARTY_NOTICES.md`, the engine versions in
  `app_licences.dart` and the list in `tool/engine_source.ps1` (then delete the old zip in
  build\dist so it's remade) if media_kit's libs change. Tests: `test/licences_test.dart`.

## ✕ on notices (0.1.30)
- **What the user asked for:** a close button on the notices at the bottom of the screen, next
  to Undo, to get rid of them quickly.
- **How:** one line in `buildTheme` (`ui/theme.dart`): `snackBarTheme: SnackBarThemeData(showCloseIcon:
  true)`, so every SnackBar gets the ✕ (after any action like Undo) without touching each one,
  and new ones get it automatically. The ✕ just hides the notice; it never does the action.
  Don't add "Dismiss"/"OK" SnackBarActions: the ✕ already does that.
- **Tests:** `test/notice_close_test.dart` (default, Midnight, Forest and a light theme).
  Picture: `flutter test tool/notice_close_preview_test.dart` (loads the real icon font).
- **15 seconds each, even while waiting** (1 Oct 2026, 0.1.40, user's request: notices close
  after 15 s, "applied even when they aren't visible to prevent excessive spamming"). Flutter
  keeps a notice with a button (Undo, Start over) up until it's closed (`persist` defaults to
  true with an action), and every notice raised meanwhile queued behind it. Now
  `NoticeMessenger` (`ui/widgets/notices.dart`, in `MaterialApp.builder` with `appMessengerKey`,
  so every `ScaffoldMessenger.of(context).showSnackBar` goes through it) keeps its own queue: each
  notice gets a 15 s timer from when it's asked for; on screen it's then closed, still waiting
  it's dropped unseen. Shown notices last their own time if shorter (buttons: 15 s). The same
  words as one showing or waiting aren't queued again. `clearSnackBars` empties the queue too.
  A notice waiting gets the current one's controller back (no caller uses it). Tests:
  `test/notices_test.dart`.

## Colour codes and sharing themes (0.1.29)
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

## What's new after an update (0.1.28)
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
  after start from `main.dart`; `WhatsNewDialog` shows "HomeTunes has been updated from x to y",
  then "Version y" + notes for each release, with **Open release page** and **OK**. `NotesText`
  draws `-` bullets (indented ones as ◦), numbered lines, `#` headings, `**bold**`, and drops `code` marks and link markup. If
  GitHub can't be reached, it still shows the version and why, with the release page button. A
  build with no published notes (a test build) shows nothing. The "Update to x?" dialog now
  uses `NotesText` too. **Settings › About › What's new in this version** shows this
  version's notes any time.
- **For releases:** because the pop-up reads the release pages, always publish with
  `-NotesFile` so the page starts with `## What's new in <version>`. When several versions
  go out as one release (0.1.25–0.1.28), put all of their changes in that one notes file.
- **Tests:** `test/whats_new_test.dart`. Picture: `flutter test tool/whats_new_preview_test.dart`.

## Equaliser (0.1.10)
- **Where:** `EqualizerModel` (`equalizer.json`, included in backups) and `models/eq_preset.dart`.
  The screen is `ui/screens/equalizer_screen.dart`, opened from Settings › Playback, from Now
  Playing, and from the icon on the Settings › Audiobooks switch.
- **Presets:** ten bands, 31 Hz to 16 kHz (`eqBands`).
  - Built-ins: Flat, Bass boost, Treble boost, Vocal, Rock, Pop, Classical, Spoken word and
    Headphones. Each one that boosts also turns the overall level down.
  - Editing a built-in stores an override. It shows "· edited", and "Restore default" or "Restore
    all presets" removes the override. Moving the sliders back to the original counts as not edited.
  - Your own presets ("New", copied from the current one) can be renamed and deleted. Deleting one
    in use falls back to Flat or Spoken word.
- **Music vs audiobooks:**
  - `musicPresetId` (default Flat) and `bookPresetId` (default Spoken word) hold the two choices.
    `separateBooks` is on by default and is the "Separate equaliser for audiobooks" switch in
    Settings › Audiobooks. When it's off, books use the music preset.
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
- **Android:** the arm64 `libmpv.so` includes `equalizer` and `scaletempo2`. The equaliser was
  confirmed working on the phone in logcat. To check it again:
  `adb logcat | Select-String "HomeTunes: equaliser|lavfi|Disabling filter"`.

## Editing several albums, books or songs (0.1.11)
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
  - There are no online look-ups. When the covers differ, the cover row says "--:-- Different
    for each album – choose one to give them all the same cover".
- **Several books** (`showEditBooks`): the boxes are author, narrator, series, year and genre, plus
  cover. There's no title or number in series, and no online look-ups.
- **Tests:** `test/multi_edit_test.dart`.

## Favourite albums and audiobooks (0.1.12)
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
  - A Favourites filter: All / Favourites chips on Library › Albums (and Artists, since 0.1.18:
    an artist counts when one of their albums is a favourite or one of their songs is liked), and
    a Favourites chip among the Books tab's state chips. The user chose filters only: no Home
    shelves and no separate page.
- **Tests:** `test/favourites_test.dart`.

## Quick actions and the Details page (0.1.13)
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

## Server sign-in and covers (0.1.17, 0.1.21)
- **Connecting** (`LibraryModel.connectServer`): an address typed without `http(s)://` tries
  https first, then http. If https doesn't answer and the address is on the internet (not the
  home network or Tailscale), Settings › Servers asks "Connect without encryption?" first; the
  answer is remembered for that server. Every Subsonic request carries a token (md5 of password +
  salt), never the password itself.
- **The password** (`services/secret_store.dart`, 0.1.17): kept in the system's protected storage
  (Windows Credential Manager, Android Keystore, via flutter_secure_storage), keyed by server
  address + user name, not in settings.json. An old plain-text password is moved over on first
  load. Where protected storage isn't available it stays in settings.json. Tests use an
  in-memory store, only in debug builds.
- **Covers for the media controls** (`services/server_art_cache.dart`, 0.1.21): server cover
  addresses carry the login token, so the notification, lock screen and Windows overlay are
  given a downloaded file instead (`<data>/art/server/<md5>.img`, max 10 MB, a failed download
  waits 5 minutes). Covers inside the app still load straight from the server. The folder is
  left out of backups and cleared when the server is forgotten.
- The full list of security fixes is in `05_CODE_GUIDE.md` → "Fixed in 0.1.21", with a summary and the accepted risks in `04_ROADMAP_AND_OPEN_ITEMS.md` → Security.

## Playback log and playback guard (0.1.20)
- **Playback log** (`services/playback_log.dart`): a short diary of what the player did (songs
  opening, play/pause, going to the background, what the media controls were told, problems
  fixed). The last 400 lines are kept in `playback-log.txt` in the data folder, not in backups.
  **Settings › About › Playback log** shows it, with a copy button.
- **Playback guard** (`state/playback_guard.dart`): `SystemPlayingState` hides a pause nobody
  asked for from the system media controls for 5 s (`grace`); `StallDetector` notices "playing"
  with no movement for 10 s (not buffering or opening), and `PlayerModel` restarts the song where
  it was. If it's still stuck within a minute, it shows paused instead. Tests:
  `test/playback_guard_test.dart`.

## Android fixes worth remembering
- **Playback stopping a while after locking the phone, with the screen still saying playing
  (0.1.20).** The brief pause media_kit makes while opening each song was passed to Android,
  which dropped the background-playback service; a locked phone can't start it again. A pause
  nobody asked for is now hidden from the media controls for 5 s, a watchdog restarts playback
  that stops by itself, and Settings › About › Playback log shows what happened (see "Playback
  log and playback guard" above). Confirmed fixed by the user on 28 Sep.
- **Lock screen empty and playback stopping.** The cause was "You must specify an icon resource id
  to build a CustomAction". It's fixed by `res/raw/keep.xml`.
- **Scanning found nothing on Android 13+.** It must request READ_MEDIA_AUDIO alone. Asking for
  storage as well gave a false "granted". The app shows a banner when access is missing, and never
  scans without access, because that would wipe the library.
