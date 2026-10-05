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

## Status (5 Oct 2026)

- **Released:** the latest release is
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
- **Checks:** 550 tests passed on 0.1.58 (5 Oct), and `flutter analyze` is clean.
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
- **Code comments:** every source file has a header comment saying what it does and why. Keep
  that up for new files.
- **These notes** are also in the repo under `docs/ai-context/`, kept the same as the project
  copy. Update them when things change.
- **In progress (5 Oct):** 0.1.59, the video buttons (Enlarge on the picture, a
  full-screen music video with a normal video's controls), built on `feature/video-buttons`,
  waiting for the user to try it; and 0.1.60, an "Always on top" pin button on the PC, built on
  `feature/always-on-top` (on top of it). The open phases are D (offline server songs, after the server
  review) and E (the Audiobookshelf connection, which needs a plan). Ask the user.

## Rules the user cares about (follow these)

1. **Plain, non-technical language** in the app's UI text and in replies. Describe what the user
   will *see*, not the implementation.
2. **Each feature goes on its own branch.** Verify on the PC (analyze, test, Windows build, APK
   build and install over adb). Merge to `main` with `--no-ff` only when the user approves ("get it
   into github" = merge + push; "delete the others" = remove merged branches).
3. **Always raise the build number** (the part after `+` in `pubspec.yaml`) for every build that
   goes on the phone. Android refuses downgrades. Bump the version for each feature (0.1.x).
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
