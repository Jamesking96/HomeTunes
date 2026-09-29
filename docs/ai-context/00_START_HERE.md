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
| `02_ENVIRONMENT_AND_WORKFLOW.md` | The user's PC, paths, build/test/install commands, git, known environment traps |
| `03_FEATURES_AND_DESIGN_NOTES.md` | What each feature does and *why* it's built that way (gapless, books, lyrics, sidecars…) |
| `04_ROADMAP_AND_OPEN_ITEMS.md` | What's done and what's next (offline server songs, audiobook server), decisions, known issues |
| `05_CODE_GUIDE.md` | A plain-English tour of the code for the user: every folder and file, how the main journeys flow, scripts, tests, where to make common changes, and probable bugs spotted |

## Status (29 Sep 2026)

- **Everything is in source control.** `main` on GitHub (github.com/Jamesking96/HomeTunes) is
  **0.1.28+28**, **released as v0.1.28 on 29 Sep** (0.1.25–0.1.28 in one release; notes in
  the release page cover all four). There are no other branches.
  - Tests: 358 pass, and `flutter analyze` is clean.
  - Builds for 0.1.28 are in `build\dist` on the PC and on the GitHub release
    (https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.28). The live update check
    (`tool/probe_update_test.dart`) found it and the installer's checksum matched. Publish each
    new version the same way, always with `-NotesFile` (see `02_…` → publishing builds).
  - Not yet updated: the PC's installed copy (0.1.24) and the phone (0.1.23). Updating either
    should show the new "What's new" pop-up with 0.1.28's notes.
  - `README.md` was brought up to date for 0.1.27 on 29 Sep.
  - `docs/USER_GUIDE.md` is the user-facing download and how-to guide shown on every release, and
    `README.md` links to it. Update it when features or menu names change.
- Built and merged so far:
  - the music library, player, playlists, editing and backups
  - server streaming
  - audiobooks (3 phases)
  - gapless + ReplayGain (plan phase 1)
  - lyrics (phase 2)
  - audiobook sidecar files (Libation `.metadata.json`, covers, descriptions, PDFs)
  - Settings tidy-up (pages, search, Sleep timer page, Servers page, About) (0.1.9)
  - equaliser (0.1.10), confirmed working on the phone in logcat
  - editing several albums and books at once, with `--:--` (0.1.11)
  - favourite albums and books (0.1.12)
  - quick actions in the right-click menu and the Details page, "where it comes from" (0.1.13)
  - code-review fixes, Windows media keys, swipe to skip, Library filters and the Windows
    accessibility crash fix (0.1.14–0.1.19; see `05_CODE_GUIDE.md`)
  - the fix for playback stopping on a locked phone, plus a Playback log (0.1.20), confirmed
    fixed by the user on 28 Sep
- Every source file has a header comment saying what it does and why (added 25 Sep; keep it up
  for new files). These notes are also in the repo under `docs/ai-context/`. Update them when things change.
- **0.1.23 (29 Sep): merged into `main`, pushed and released as v0.1.23.** The user tried it and
  approved. It's installed on the phone.
  - Volume everywhere (0.1.22): volume on Now Playing (cover and lyrics) and a speaker button
    with a pop-up slider in the phone's mini player.
  - Check for updates (0.1.23): Settings › About › Check for updates + a daily check; Windows
    installs itself, the phone opens the download page. See `03_…` → Updates.
  - 306 tests pass, analyze is clean. The branches were deleted.
  - **From now on, publish every release with `tool/publish_release.ps1`**: installed copies
    look for its file names and checksum file to update themselves. The first real
    self-update (close, install, reopen) will happen with the next release after 0.1.23.
- **0.1.24 (29 Sep): colour themes, merged, pushed and released as v0.1.24.** Settings ›
  Appearance with Default / Midnight / Forest / Your own. 316 tests pass. The user approved it.
  See `03_…` → Colour themes. This is the first release 0.1.23 can update to by itself.
- **0.1.25–0.1.28 below were merged into `main` and released together as v0.1.28 on 29 Sep;
  their branches were deleted.**
- **0.1.25: advanced appearance**: saved themes with every colour (light themes too), text size, corners, plus
  `tool\switch_branch.ps1` and rule 13. Started by another session, finished by this one.
  325 tests pass, analyze clean. Waiting for the user to try it. See `03_…` → Advanced appearance.
- **0.1.26**: queue as a side drawer, artist-page albums open in place (+ Open album page,
  hover play), Settings in A–Z order with **Folders & scanning** (music + audiobook folders).
  337 tests pass. The user wants 0.1.25 and 0.1.26 released together once tried. See `03_…`.
- **0.1.27**: folder options (rescan one folder, file-type tick boxes) for music and audiobook
  folders, and the speaker icon as a mute toggle. 345 tests pass. Release 0.1.25–0.1.27
  together when the user says so (the phone still has 0.1.23).
- **0.1.28 (merged and released 29 Sep, with 0.1.25–0.1.27)**: the first start
  after an update shows a "What's new" pop-up compiled from the release pages' "What's new in x"
  sections (every version since the old one), plus **Settings › About › What's new in this
  version**. 358 tests pass, analyze clean. 0.1.23/0.1.24 copies don't record their version,
  so after updating they show just 0.1.28's page (which covers 0.1.25–0.1.28). See `03_…`.
- **In progress (29 Sep): 0.1.29, branch `feature/theme-sharing`**, not merged: a "Colour code"
  box in every colour picker (type or paste `#FF7A59`), and sharing themes: Share… gives a
  theme code to copy or a `.hometunes-theme` file, and Import a theme reads either. 371 tests
  pass, analyze clean. Waiting for the user to try it. See `03_…` → Colour codes and sharing.
- **Next after that:** nothing is agreed yet. The open phases are D (offline server songs, after the server
  review) and E (the Audiobookshelf connection, which needs a plan). Ask the user. See
  `04_ROADMAP_AND_OPEN_ITEMS.md`.
  - `05_CODE_GUIDE.md` lists probable bugs spotted while commenting the code (none fixed yet).

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
7. **Server password in backups is opt-in only.**
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
