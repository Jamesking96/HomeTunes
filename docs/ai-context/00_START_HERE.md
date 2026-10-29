# HomeTunes: start here

HomeTunes is a Spotify-style music and audiobook player for the user's own files, written in
Flutter. It runs on Windows (main desktop) and Android (a Pixel 8). It can also stream from a
Subsonic/OpenSubsonic server. The repo is **github.com/Jamesking96/HomeTunes** (it used to be
`…/hometunes`; GitHub redirects).

Read the files in this order:

| File | What it covers |
|---|---|
| `00_START_HERE.md` | Status right now, the rules that matter most, how to pick up a task |
| `01_ARCHITECTURE.md` | Code map: models, state, services, UI, data files, vendored packages |
| `02_ENVIRONMENT_AND_WORKFLOW.md` | The user's PC, paths, build/test/install/publish commands, release signing, git, known environment traps |
| `03_FEATURES_AND_DESIGN_NOTES.md` | What each feature does and *why* it's built that way (gapless, books, lyrics, sidecars…) |
| `04_ROADMAP_AND_OPEN_ITEMS.md` | What's done and what's next (offline server songs, audiobook server), decisions, security, known issues |
| `05_CODE_GUIDE.md` | A plain-English tour of the code for the user: every folder and file, how the main journeys flow, scripts, tests, where to make common changes, and probable bugs spotted |

## Status (29 Oct 2026)

- **Released 29 Oct: [v0.2.6](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.2.6)** (0.2.6+114), covering 0.2.5–0.2.6: the TV review fixes, TV posters/pictures and sounds, the TV Videos type row / Filter / sorts, Servers notes, backup and download fixes, and video shuffle (all below). `feature/tv-review-fixes` was merged into `main` (`--no-ff`) and deleted: **`main` is the only branch again.** The engine source zip was reused from v0.2.4 (pubspec.lock unchanged). Both TVs (192.168.1.82 and 192.168.1.106) have 0.2.6+114.

- **Now (28 Oct): `feature/tv-review-fixes`, 0.2.5+108, not merged.** Fixes from the code and TV
  review (Claude Docs "HomeTunes 0.2.4 — Code & TV Review"; the user chose TV bugs & layout plus
  downloads safety, not the title clean-up). OK on a collection/book/series opens at once (AppNav
  `_afterFrame` asks for a frame; before, a still screen waited for the next key press); Back with
  the menu open goes back into the page; ↑ ↓ don't cross into the menu, and entering the menu lands
  on the place showing; the focused row is kept 10–60 % down its list (`tvReveal`, instant
  scrolling) and pages scroll right up near their top; a bottom margin; the hint bubble fades after
  4 s (the user's choice) and comes back with any press; one hint wording style; dark TV notices
  (raised above the player's controls); Carry on shows the episode first; long descriptions open in
  full with OK; TV Settings hides Your edits and Swipe gestures (the user's choice) and servers that
  can't play a kind yet; a focus ring on filled buttons and switches; Downloads pages open over the
  tab showing; player: no empty preview box (server videos are never previewed), 10 s first seek
  step, ↓ from the bar goes to Play, one title for films, "–:––" before the length is known;
  downloads: a size guess when the length isn't known, a playing temporary copy is never cleared, a
  folder move counts once copied. `flutter analyze` clean. The APK is in `build\dist` (signed,
  108) was installed on the Family room TV on 28 Oct 23:39. Then 0.2.5+109 (29 Oct): the server
  card's ⋮ menu works with the remote (each item was a ListTile the remote stopped on, so OK did
  nothing; now `_MenuRow` with ExcludeFocus); ServerVideosModel ignores updates once closed down
  (a test race). 846 tests pass. Built 29 Oct 00:08–00:11: `HomeTunes-Setup-0.2.5.exe`, the
  Windows zip and the APK in `build\dist`. 109 went on the TV at 00:14. Then (29 Oct, the user's
  PC backup `E:\Applications\HomeTunes\downloads\HomeTunes-backup-2026-10-29.htbackup` merged into
  the TV): 0.2.5+110 reloads Videos and Downloads after a restore (they weren't, so the old data was
  saved back over it) and shows "Backup restored" over the app; 0.2.5+111 leaves server pictures
  (art/server-video, ~5,400 files, nearly all of the 121 MB) out of backups and skips them in old
  ones: the TV ran out of memory ("Exhausted heap space") and the restore failed silently. 111 is on
  the TV; the backup merged (the PC's posters show), and the TV stayed signed in to the PC's Jellyfin
  (Sync now worked). On the TV, Import uses File Manager + as the file chooser (no system one).
  847 tests pass. Then 0.2.5+112 (29 Oct, the user's asks):
  the TV's Hold-OK menus have **Change poster** (collections) and **Change picture** (videos):
  Search online on a full-screen TV page (`tv/tv_pictures.dart`), Choose a picture file, Use the
  automatic one (no Pick a frame on the TV: local files only, and its window doesn't fit); **TV
  sounds** (the TV's own navigation/click effects via MainActivity `playSound`, `services/tv_sounds.dart`,
  played from TvFocus only when focus moves, plus OK/Back; Settings › Appearance › Sounds on the TV,
  saved only when off); Settings › Servers' Downloads and Temporary copies start with a where-and-how
  note worded per device (`HowItWorks`). 853 tests pass. 112's APK and PC installer are in
  `build\dist` (29 Oct 10:56–11:0x); the APK went on the TV at the user's request (29 Oct 11:11).
  Then 0.2.5+113 (29 Oct, the user's asks): Jellyfin videos take their **type** from their library's
  name (the user's server has Anime / Shows / Movies; Anime was filed as TV) via `state/video_types.dart`
  (`videoType`: Film(s)/Movies → Films, TV/Shows/TV Shows/Series → TV, "anime" → Anime, others keep
  their name). The TV's Videos tab has a type row under the tabs (All · Anime · TV · Films, the user's
  choice of layout) applying in every tab, a **Filter** button (Watched, Genre, Source; the user's
  picks) and sorts **Most episodes**, **Not watched first** and **Reverse the order**. 858 tests pass.
  113's APK and PC installer are in `build\dist` (29 Oct 12:14–12:16); the APK went on the TV at the user's request (29 Oct 13:59).
  Then 0.2.6+114 (29 Oct evening, the user's ask, "for all platforms"): **video shuffle**
  (`state/video_shuffle.dart`, `ui/widgets/video_shuffle_ui.dart`). Shuffle on a collection's page
  (PC/phone: button beside Play, the card / contents panel menus; TV: button beside Play) plays
  the seasons "in the shuffle" in a random order, each once, stopping at the end; a season's
  heading (PC/phone) or More options › Shuffle <season tab> (TV) shuffles just that season.
  **Seasons in the shuffle** (⚙ beside Shuffle; TV: More options) ticks seasons in/out, kept per
  collection in videos.json `shuffle` (only differences from the default; default in: seasons,
  parts, loose episodes; out: Specials, special-marked seasons, Extras); merged from backups, follows
  renames. `VideoSession.shuffle` drives next/previous/Up next/the bottom bar; the player shows
  "Shuffling <label> · n of m" with × (PC/phone) or Stop shuffling (TV options). 866 tests pass.
  114's APK, PC installer and zip are in `build\dist` (29 Oct 21:29–21:36); the APK went on **both
  TVs** at the user's request (29 Oct 21:37).
  The PC's C: drive was full (250 MB free) on 28 Oct; Flutter's old temp folders were cleared with
  the user's OK (about 1.3 GB free after). Watch the space before builds.
- **Released 28 Oct: [v0.2.4](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.2.4)** (0.2.4+106), covering 0.2.1–0.2.4: the whole Servers & Downloads plan (Jellyfin videos, the Source filter, downloads, temporary copies) and the TV fixes of 28 Oct (the user: "Everything here looks good to me"). All four step branches were merged into `main` (`--no-ff`) and deleted: **`main` is the only branch again.** Next: more TV work (the user: "We still have some things for TVs we want to work on"); the history of the four steps below is kept for reference.
- **Released 23 Oct: [v0.2.0](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.2.0)** (0.2.0+101), covering 0.1.82–0.2.0: the Android TV interface (all seven steps), the app icon, Play buttons showing what's playing, the even volume fade and the video seek preview. `feature/android-tv` was merged into `main` and deleted: **`main` is the only branch.** The user has seen some TV issues still to fix (to be listed).
- **Now (25 Oct):** the Servers & Downloads plan (see `04_`). Step 1, Jellyfin videos (0.2.1+102),
  is on `feature/jellyfin-videos`: a Jellyfin server switched on for Videos fills the Videos tab,
  plays from the server and keeps places in step both ways (`03_…` → Jellyfin videos). Versions
  after 0.2.0 count on as 0.2.x. The user's answers (27 Oct): downloads go in HomeTunes' data
  folder by default, with a setting to pick another folder; Keep offline and next-episode
  downloads run in the background on the phone, with a message saying so and a setting to turn
  it off; **all four steps are released together** once step 4 is done (no release per step).
  The 0.2.1+102 APK was built 27 Oct (not installed anywhere yet). Step 2, the Source filter
  (0.2.2+103), is on `feature/source-filter`, branched from `feature/jellyfin-videos`. Step 3,
  downloads (0.2.3+104: Download… with the copy chosen each time, Keep offline, next episodes,
  Wi-Fi only, a space limit, Make it mine, a Downloads page), is on `feature/downloads`, branched
  from `feature/source-filter` (`03_…` → Downloads); the TV got its download options there too.
  Step 4, temporary copies (0.2.4+105: Save a copy while streaming, cleared n days after it's
  finished or never, its own space, Keep, Clear now), is on `feature/temporary-copies`, branched
  from `feature/downloads` (`03_…` → Temporary copies). That's all four steps built; they're
  released together once the user has tried them. 28 Oct (0.2.4+106, same branch): fixes the
  user asked for after trying it on the Family room TV (Remove downloaded videos once watched;
  the Download folder row; Back twice to leave on the TV; Back hides the video controls first).
- **The TV over the network (28 Oct):** the Family room TV (Sony BRAVIA BF1, Google TV,
  Android 12, armeabi-v7a) is at 192.168.1.82 with network debugging allowed for the PC, so
  `adb connect 192.168.1.82:5555` then `adb install -r build\dist\HomeTunes-<v>-android.apk`
  updates it (adb is in `%LOCALAPPDATA%\Android\Sdk\platform-tools`). `adb shell input keyevent`
  presses remote keys and `screencap` takes screenshots; send one key per `adb shell` call with a
  screenshot between, as several in one call get dropped. **Second TV (29 Oct):** 192.168.1.106:5555
  is a Sony KD-55XH8096 ("BRAVIA 4K UR3", Android 10, armeabi-v7a, 1920×1080), network debugging
  allowed for the PC; the user asked for HomeTunes on it too, so builds go to **both TVs** when the
  user says. Scripts `C:\Temp\ht\tv2_shot.ps1` / `tv2_seq.ps1` (`-Dev`). The Jellyfin server
  ("test", http://192.168.1.81:8096, OrangeKnight) was filled in on it except the password (never
  read from storage; the user types it), and wasn't saved; the 114 install closed that dialog.
- **Latest (13 Oct):** 0.1.82 (an album's or playlist's Play button shows when it's playing) 0.1.83 (the volume sliders fade evenly to silence; the EQ level is right) and 0.1.84 (a preview picture above a video's progress bar) are merged into `main` and pushed, not yet released; v0.1.81 (12 Oct) is the latest release. The Android TV work (0.2.0) is on `feature/android-tv`, with `main` merged in. See `04_`, Source control.
- **Android TV (22 Oct):** the TV work (0.2.0+94) is on `feature/android-tv`, pushed to GitHub. The user tried it on the TV: the remote now stays on the open page; HomeTunes' own folder browser for Add folder isn't tried yet. The user is moving to another PC; see `04_`, Platforms plan, Android TV progress.
- **Released:** the latest release is
  [v0.1.70](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.70) (6 Oct), which
  covers 0.1.63–0.1.70 in one release: the video sleep timer, sidebar quick links (playlists
  too), the volume % bubble, special seasons, playlist icons, a video's priority in small
  windows, Ascending / Descending on every sort, and the video volume sliders following the
  boost at once. Before it,
  [v0.1.62](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.62) (5 Oct), which
  covers 0.1.59–0.1.62 in one release: Enlarge on the video picture and Leave full screen in
  full screen, full-screen music videos with a normal video's controls, an "Always on top" pin
  on the PC, and a volume boost (every volume slider can go up to 500 %). Before it,
  [v0.1.58](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.58) (5 Oct), which
  covers 0.1.55–0.1.58 in one release: video playback stats in the Playback log, smoother music
  video syncing, and videos on phones drawn straight from the video chip (music videos keep the
  usual drawing). Before it,
  [v0.1.54](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.54) (5 Oct): editing one
  song's album name moves just that song instead of renaming the whole album. Before it,
  [v0.1.53](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.53) (3 Oct), which
  covers 0.1.45–0.1.53 in one release: the Home revamp, Settings › Servers for several servers,
  Shift + click and Esc in select mode, search boxes in the filter drop-downs, the no-internet
  warning, the update check at every start, the Artists tab's list / grid, and artist pictures.
  Before it,
  [v0.1.44](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.44) (1 Oct): Details
  pages for videos and collections (where each detail came from, what's inside the file). Before
  that, the same day,
  [v0.1.43](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.43) (the bottom bar
  follows the video again),
  [v0.1.42](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.42) (a loading page while
  a video opens),
  [v0.1.41](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.41) (copyable titles,
  videos in Search, shrink to fit small windows) and
  [v0.1.40](https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.40) (1 Oct), which
  covers 0.1.31 and 0.1.40 (0.1.32 was renumbered 0.1.40 before release: videos are a whole new
  feature). It adds **videos** (the Videos tab, music videos on Now Playing, the video engine),
  the resizable / foldable sidebar, notices that close after 15 s, and 0.1.31's **MIT licence**
  ("Copyright (c) 2026 Jamesking96"). The engine is media_kit's video build; its licences
  (`THIRD_PARTY_NOTICES.md`, `licenses/ENGINE-COMPONENTS.txt`, the source in
  `HomeTunes-audio-engine-source.zip` from `tool/engine_source.ps1`) are explained in `04_…`
  (Music videos, "Done 1 Oct"). See `03_…` → Licence, which includes the rule about GPL
  libraries.
- **Checks:** 592 tests passed on 0.1.70 (6 Oct), and `flutter analyze` is clean.
- **Build script stall (6 Oct):** `tool\build_release.ps1 -Android` has stopped after Gradle
  makes the APK (the script's process goes away before copying it). When that happens, copy
  `build\app\outputs\flutter-apk\app-release.apk` to `build\dist\HomeTunes-<ver>-android.apk`
  and check it with apksigner (JAVA_HOME = Android Studio's jbr), as the script would.
- **Devices:** the phone had 0.1.58 on 5 Oct (the user tested the video builds on it). Installed Windows copies update
  themselves from GitHub releases, so the PC's copy may be newer.
- **Publishing:** every release goes out with `tool/publish_release.ps1 -NotesFile …` (see `02_…`
  → publishing builds). Installed copies look for its file names and checksum file to update
  themselves. When versions are released together, the notes must cover all of them, because
  "What's new" lists release pages, not versions.
- **User-facing docs:** `docs/USER_GUIDE.md` is the download and how-to guide shown on every
  release, and `README.md` links to it. Update both when features or menu names change.
- **What's built** (details and the *why* in `03_…`, per-release fixes in `05_…`):
  - 0.1.0–0.1.9: music library, player, playlists, editing and backups; server streaming;
    audiobooks; gapless + ReplayGain; lyrics; audiobook sidecar files; the Settings tidy-up
  - 0.1.10–0.1.13: equaliser, editing several albums or books at once, favourites, quick actions
    and the Details page
  - 0.1.14–0.1.19: code-review fixes, Windows media keys, server password in protected storage,
    swipe to skip, Library filters, the Windows accessibility crash fix
  - 0.1.20: keeps playing on a locked phone (confirmed by the user on 28 Sep), plus the Playback log
  - 0.1.21: all ten security-review fixes (see `04_…` → Security)
  - 0.1.22–0.1.24: volume everywhere, Check for updates (Windows installs itself, the phone opens
    the download page), colour themes
  - 0.1.25–0.1.28: advanced appearance (saved themes, every colour, text size, corners), queue
    drawer, Settings in A–Z order with Folders & scanning, folder options, mute, the What's new
    pop-up
  - 0.1.29–0.1.30: colour codes, sharing themes, a ✕ on every notice
  - 0.1.31: MIT licence and third-party notices
  - 0.1.40: videos (Videos tab, collections, seasons, music videos), the resizable sidebar,
    notices that close after 15 s
  - 0.1.41: copyable titles, videos and collections in Search, shrink to fit small windows
  - 0.1.42: a loading page while a video opens (the user confirmed it works)
  - 0.1.43: the bottom bar follows the video again (confirmed by the user); single "What's new"
    heading on release pages
  - 0.1.44: Details pages for videos and collections
  - 0.1.45–0.1.53 (released together as v0.1.53): Home revamp (videos, Jump back in, recently
    played music), Settings › Servers with several servers per kind (a framework; only the main
    Subsonic server streams), Shift + click ranges and Esc in select mode, search in the filter
    drop-downs, the no-internet warning, the update check at every start, the Artists tab's
    list / grid, and artist pictures
  - 0.1.54: one song's album edit moves just that song (the "also update the album" box starts
    unticked for album name / album artist changes)
  - 0.1.55–0.1.58 (released together as v0.1.58): video playback stats in the Playback log,
    music videos kept in step by speed instead of jumps, videos on phones drawn straight from
    the video chip (Settings › Videos › Smoother video on phones), music videos on the usual
    drawing. The user's logs showed no dropped pictures afterwards
  - 0.1.59–0.1.62 (released together as v0.1.62): Enlarge on the video picture, Leave full
    screen in full screen, full-screen music videos with a normal video's controls, the
    "Always on top" pin (PC), and the volume boost (Settings › Playback sets how far every
    volume slider goes, up to 500 %)
  - 0.1.63–0.1.70 (released together as v0.1.70, 6 Oct): sleep timer for videos,
    quick links in the sidebar (albums, artists, audiobooks, collections, videos, playlists),
    the volume % bubble, special seasons with titles from a list, playlist icons and pictures,
    the video first in small windows, Ascending / Descending on every sort, and the video
    volume sliders following the boost at once
- **Code comments:** every source file has a header comment saying what it does and why. Keep
  that up for new files.
- **These notes** are also in the repo under `docs/ai-context/`, kept the same as the project
  copy. Update them when things change.
- **Next:** nothing agreed yet. The open phases are D (offline server songs, after the server
  review) and E (the Audiobookshelf connection, which needs a plan). The Platforms plan (Android TV, then
  Android Auto, then Linux, reordered 13 Oct; see `04_…`) is agreed but paused; its phases are planned as 0.2.x (the next level of development), only
  once the user starts them.
  Ask the user.

## Rules the user cares about (follow these)

1. **Plain, non-technical language** in the app's UI text and in replies. Describe what the user
   will *see*, not the implementation.
2. **Each feature goes on its own branch.** Verify on the PC (analyze, test, Windows build, APK
   build and install over adb). Merge to `main` with `--no-ff` only when the user approves ("get it
   into github" = merge + push; "delete the others" = remove merged branches).
3. **Always raise the build number** (the part after `+` in `pubspec.yaml`) for every build that
   goes on the phone. Android refuses downgrades. Bump the version for each feature or fix: it stays on **0.1.x** (0.1.71, 0.1.72…) for
   work on the app as it is. **0.2.0 is kept for the next level of development** (the user,
   7 Oct, correcting the 6 Oct note that the next release would be 0.2.0): don't move to 0.2.x
   until the user starts that stage. The build number keeps counting up (73 for 0.1.71).
4. **Before building or testing on the PC, check that the user isn't running HomeTunes or a
   `flutter run` (VS Code F5).** Never kill their app. `LNK1168` during a Windows build means the
   app is open: skip the Windows build and say so. (A process check whose own command line contains
   the search pattern will match itself. Ignore your own PID.)
5. **Ask before installing on the phone.** It's usually plugged in, but may have been removed.
6. **Settings placement:**
   - Audiobook-related settings go in **Settings → Audiobooks** (the audiobook folders also show
     in **Folders & scanning**, the user's choice on 29 Sep).
   - Settings pages stay in **A–Z order** (0.1.26).
   - Playback settings go in **Settings → Playback**.
   - Online look-up switches go in **Settings → Online lookups**.
   - The sleep timer has its own **Settings → Sleep timer** page.
   - Every new setting gets a `SettingTarget` and an entry in `settingsCatalog` so search finds it.
7. **Backups never contain the server password** (since 0.1.21). After a restore on a new device,
   the user types it again. Don't add an option to include it.
8. **Never reproduce copyrighted lyrics** (not in mock-ups, tests or probes either). Use invented
   lines. `tool/probe_lyrics.dart` prints counts only.
9. Don't do things the user didn't ask for without flagging them. Surprising findings (e.g. the
   tag writer dropping tags) are reported plainly.
10. Ask the server questions and the Android "All files access" question only when that work comes
    up.
11. The user's email is only for commit attribution.
12. **Never take screenshots of the user's PC screen or open app windows on it to check how
    something looks.** They may be using the PC (on 29 Sep a capture caught a game they were
    playing). Draw screens off-screen instead (`tool/theme_preview_test.dart` shows how), and
    ask before anything that shows up on their screen.
13. **Before any git command that changes the working folder (checkout, switch, merge, pull,
    reset, stash), run `git status -sb` and look.** If there are unsaved changes you didn't make,
    or you're not on the branch you expected, **stop and ask**: another session or VS Code may be
    working there. Switch branches with `tool\switch_branch.ps1 <branch>` (it refuses when
    anything is unsaved or a debug run is going). On 29 Sep a session ran `git checkout main`
    while another session's edits were open on `feature/advanced-themes`; they survived only by
    luck.

## How to pick up a task

1. Read `04_ROADMAP_AND_OPEN_ITEMS.md` for what's next and what's undecided.
2. For anything bigger than a small fix, write a **plan first** and agree it with the user. Past
   plans were published as artifacts: "HomeTunes Sound & Offline Plan" covers everything still
   planned. Ask the user the open questions from the plan before building.
3. Create a branch from the right base, build, and verify (see `02_…`). Then report what the user
   will see and anything that couldn't be verified.
