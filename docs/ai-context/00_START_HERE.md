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
| `04_ROADMAP_AND_OPEN_ITEMS.md` | What's next (equaliser, offline server songs), open decisions, known issues |

## Status (25 Sep 2026)

- **Everything is in source control.** The repo is `main` on GitHub
  (github.com/Jamesking96/HomeTunes). There are no other branches and no uncommitted work.
  Version **0.1.8+7**.
- Built and merged so far:
  - the music library, player, playlists, editing and backups
  - server streaming
  - audiobooks (3 phases)
  - gapless + ReplayGain (plan phase 1)
  - lyrics (phase 2)
  - audiobook sidecar files (Libation `.metadata.json`, covers, descriptions, PDFs)
- Builds for 0.1.8 are in `C:\Users\James.Miller\source\hometunes\build\dist\` on the PC
  (not in git). 0.1.8 (versionCode 7) is installed on the phone.
- Tests: 149 pass (`flutter test`). `flutter analyze` is clean.
- These notes are also in the repo under `docs/ai-context/`. Update them when things change.
- **Next up:** phase 3, the equaliser (see `04_ROADMAP_AND_OPEN_ITEMS.md`).

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
   app is open: skip the Windows build and say so.
5. **Settings placement:** audiobook-related settings go in **Settings → Audiobooks**. Playback
   settings go in **Settings → Playback**. Online look-up switches go in **Settings → Online lookups**.
6. **Server password in backups is opt-in only.**
7. **Never reproduce copyrighted lyrics** (not in mock-ups, tests or probes either). Use invented
   lines. `tool/probe_lyrics.dart` prints counts only.
8. Don't do things the user didn't ask for without flagging them. Surprising findings (e.g. the
   tag writer dropping tags) are reported plainly.
9. The user's email is only for commit attribution.

## How to pick up a task

1. Read `04_ROADMAP_AND_OPEN_ITEMS.md` for what's next and what's undecided.
2. For anything bigger than a small fix, write a **plan first** and agree it with the user. Past
   plans were published as artifacts: "HomeTunes Sound & Offline Plan" covers phases 1–4. Ask the
   user the open questions from the plan before building.
3. Create a branch from the right base, build, and verify (see `02_…`). Then report what the user
   will see and anything that couldn't be verified.
