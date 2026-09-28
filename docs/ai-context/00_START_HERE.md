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

## Status (28 Sep 2026)

- **Everything is in source control.** `main` on GitHub (github.com/Jamesking96/HomeTunes) is
  **0.1.20+20**. There are no other branches.
  - Tests: 274 pass, and `flutter analyze` is clean.
  - Builds for 0.1.20 are in `build\dist` on the PC and can be downloaded from the GitHub release
    (https://github.com/Jamesking96/HomeTunes/releases/tag/v0.1.20). Publish each new version
    the same way (see `02_…` → publishing builds).
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
- **Next:** nothing is agreed yet. The open phases are D (offline server songs, after the server
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
   - Audiobook-related settings go in **Settings → Audiobooks**.
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

## How to pick up a task

1. Read `04_ROADMAP_AND_OPEN_ITEMS.md` for what's next and what's undecided.
2. For anything bigger than a small fix, write a **plan first** and agree it with the user. Past
   plans were published as artifacts: "HomeTunes Sound & Offline Plan" covers everything still
   planned. Ask the user the open questions from the plan before building.
3. Create a branch from the right base, build, and verify (see `02_…`). Then report what the user
   will see and anything that couldn't be verified.
