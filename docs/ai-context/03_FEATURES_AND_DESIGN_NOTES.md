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
- **Servers:** the music server, then an Audiobooks group. That group has the "Audiobooks from the
  music server" switch (`serverBooks`) and a placeholder for a separate audiobook server (phase E).
- **About** shows the version (package_info_plus) and the data folder, with "Open folder" on Windows.
  It also has **Check for updates** and **Check for updates automatically** (0.1.23), **What's new
  in this version** (0.1.28), **Playback log** (0.1.20) and **Licences** (0.1.31); see the
  sections below.

## Loading page while a video opens (1 Oct 2026, 0.1.42, branch `feature/video-loading`)
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
  real page, which needs the video engine). Not yet seen in a real window.

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
