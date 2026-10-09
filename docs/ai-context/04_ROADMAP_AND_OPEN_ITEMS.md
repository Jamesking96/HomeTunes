# Roadmap and open items

## The agreed plan: "HomeTunes Sound & Offline Plan"
The plan is published as an artifact (https://claude.ai/artifact/QsNhvBvSRx69PNvz3ULyjp), updated
25 Sep 2026 (version 5) with the user's answers and two new pieces of work. Agreed order:
**A settings tidy-up → B equaliser → C multi-album (and book) edit → D offline server songs.**
A, B and C are finished; D and E are still open.

Finished work has a one-line row here. How each piece was built is in `03_FEATURES_AND_DESIGN_NOTES.md`
(`03_…`), and the fix-by-fix history of 0.1.14–0.1.24 is in `05_CODE_GUIDE.md` → "Things spotted
while commenting".

| Phase | Status |
|---|---|
| 0: engine check | Done. The arm64 `libmpv.so` has lavfi `equalizer` and `scaletempo2`, but no `superequalizer` or rubberband. The equaliser was confirmed running on the phone (logcat, 25 Sep). |
| 1: gapless + ReplayGain | Done |
| 2: lyrics | Done. See `03_…` → Lyrics |
| Book sidecar files | Done. See `03_…` → Book sidecar files |
| A: settings tidy-up | Done (0.1.9). See `03_…` → Settings |
| B: equaliser (was phase 3) | Done (0.1.10), confirmed on the phone in logcat. See `03_…` → Equaliser |
| C: multi-album + multi-book edit | Done (0.1.11). See `03_…` → Editing several albums, books or songs |
| Favourite albums & books | Done (0.1.12) |
| Quick actions + Details page | Done (0.1.13) |
| Code-review fixes, Windows media keys, swipe to skip, Library filters, Windows accessibility crash fix | Done (0.1.14–0.1.19). See `05_CODE_GUIDE.md` |
| Lock-screen playback fix + Playback log | Done (0.1.20), confirmed by the user on 28 Sep |
| Security fixes (all ten) | Done, released as v0.1.21 (28 Sep). See "Security" below |
| Volume everywhere (0.1.22) | Done, released in v0.1.23 (29 Sep) |
| Check for updates (0.1.23) | Done, released as v0.1.23 (29 Sep). See `03_…` → Updates |
| Colour themes (0.1.24) | Done, released as v0.1.24 (29 Sep). See `03_…` → Colour themes |
| Advanced appearance (0.1.25) | Done, released in v0.1.28 (29 Sep). See `03_…` → Advanced appearance |
| Queue drawer, artist albums in place, Settings A–Z (0.1.26) | Done, released in v0.1.28 (29 Sep) |
| Folder options + mute (0.1.27) | Done, released in v0.1.28 (29 Sep) |
| What's new after an update (0.1.28) | Done, released as v0.1.28 (29 Sep) |
| Colour codes and sharing themes (0.1.29) | Done, released in v0.1.30 (29 Sep) |
| ✕ on notices (0.1.30) | Done, released as v0.1.30 (29 Sep) |
| MIT licence + third-party notices (0.1.31) | **Merged (30 Sep), not released yet.** Rebuild before releasing. See `03_…` → Licence |
| Selectable titles, search for videos, scaling with the window (0.1.41) | Done, released as v0.1.41 (1 Oct) |
| Loading page while a video opens (0.1.42) | Done, released as v0.1.42 (1 Oct); the user confirmed it works |
| Bottom bar / video volume linked again; single "What's new" heading (0.1.43) | Done, released as v0.1.43 (1 Oct); the user confirmed it works |
| Details for videos and collections (0.1.44) | Done, released as v0.1.44 (1 Oct); the user approved it |
| Home revamp: videos on Home, Jump back in, recently played music (0.1.45) | Done, released in v0.1.53 (3 Oct; built 1 Oct). See `03_…` → Home revamp |
| Servers page: several servers per kind, Music / Audiobooks / Videos (0.1.46) | Done, released in v0.1.53 (3 Oct; built 1 Oct). The user chose "framework now": only the main Subsonic server streams. See `03_…` → Servers page |
| Shift + click selects everything between two items (0.1.47) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Shift + click |
| Esc cancels a selection (0.1.48) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Esc cancels a selection |
| Search box in the filter drop-downs (0.1.49) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Search in filter drop-downs |
| No-internet warning at start-up and before online features (0.1.50) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → No internet warning |
| Update check every time the app opens, not once a day (0.1.51) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Update check at start-up |
| Artists tab: list or grid (0.1.52) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Artists tab: list or grid |
| Artist pictures: change the picture an artist shows (0.1.53) | Done, released in v0.1.53 (3 Oct; built 2 Oct). See `03_…` → Artist pictures |
| Fix: editing one song's album renamed the whole album (0.1.54) | Done, released as v0.1.54 (5 Oct). See `03_…` → One song's album edit |
| Video playback stats in the Playback log, step 1 of the video smoothness plan (0.1.55) | Done, released in v0.1.58 (5 Oct; built 5 Oct). See `03_…` → Video playback stats |
| Smoother music videos: small drifts caught up with speed instead of jumps (0.1.56) | Done, released in v0.1.58 (5 Oct). See `03_…` → Smoother music videos |
| Smoother video on phones: drawing straight from the video chip, music video jumps aim ahead, more detail in the log (0.1.57) | Done, released in v0.1.58 (5 Oct). The user's log: normal videos now drop no pictures, but music videos went badly out of step. See `03_…` → Smoother video drawing on phones |
| Music videos back to the usual drawing, skips noted in the log (0.1.58) | Done, released as v0.1.58 (5 Oct), covering 0.1.55–0.1.58. The user's log (5 Oct, 12:31): the music video played 1:26 with no dropped pictures and no jumps (one 212 ms slow frame at the start). See `03_…` → Music videos back to the usual drawing |
| Video buttons: Enlarge on the picture, Leave full screen in full screen, a full-screen music video with a normal video's controls (0.1.59) | Merged into `main` and pushed 5 Oct (the user tried it: "all looks good"); released in v0.1.62 (5 Oct). See `03_…` → Video buttons on the picture |
| Always on top: a pin button on the PC (player bar, Now Playing, Details, full screen) (0.1.60) | Merged into `main` and pushed 5 Oct; released in v0.1.62 (5 Oct). See `03_…` → Always on top |
| Volume boost: up to 500 % like VLC, Settings › Playback (0.1.61) | Merged into `main` and pushed 5 Oct (reworked by 0.1.62); released in v0.1.62 (5 Oct). See `03_…` → Volume boost |
| Volume boost through the volume sliders: the setting is the sliders' top, up to 500 % (0.1.62) | Merged into `main` and pushed 5 Oct; released as v0.1.62 (5 Oct), covering 0.1.59–0.1.62. See `03_…` → Volume boost through the volume sliders |
| Sleep timer for videos (0.1.63) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_…` → Sleep timer for videos |
| Quick links in the sidebar (0.1.64) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). Playlists added as links the same day (build +66). See `03_`, Quick links in the sidebar |
| Volume percentage bubble above the volume sliders while changing them, can be turned off (0.1.65) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_`, Volume percentage bubble |
| Special seasons: mark a season special with a title from a list kept in Settings; badge, listed last, skipped by Up next (0.1.66) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_`, Special seasons |
| Playlist icons: a built-in icon and colour, or a picture (0.1.67) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_`, Playlist icons |
| Small windows: a showing video keeps its size; text and controls shrink to a usable minimum (0.1.68) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). Needs the user's eye in a small window. See `03_`, A video in a small window |
| Ascending / descending for every sort (0.1.69) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_`, Ascending / descending |
| Fix: the video volume sliders follow the volume boost as soon as it's changed (0.1.70) | Merged into `main` and pushed 6 Oct (the user: "Everything works great"); released in v0.1.70 (6 Oct). See `03_`, Fix: video volume sliders |
| Fix: Next video sometimes replayed the same video (0.1.71) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. See `03_`, Fix: Next video sometimes replayed |
| Now Playing in a small window (buttons over the video; the cover fades, the buttons shrink) and a smallest window size (0.1.72) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. Smallest size: `windows/runner/window_limits.h`. See `03_`, Now Playing in a small window |
| Rescan buttons on Your Library and Audiobooks, like the Videos tab's (0.1.73) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. See `03_`, Rescan buttons |
| Audiobooks sub-tabs (Series first, then All / In progress / Not started / Finished / Favourites), each with Your Library's filter bar, chips and sorting (0.1.74) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. See `03_`, Audiobooks sub-tabs |
| Audiobook series: a page per series, series cards, favourite series, series in the sidebar (0.1.75) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. Step 1 of 2 (the user: "Go with your suggestions"). See `03_`, Audiobook series |
| Edit series: name, author, description, order, add / take out books, picture (0.1.76) | Merged into `main` 8 Oct and released as v0.1.76 (8 Oct), covering 0.1.71–0.1.76. Step 2 of 2. See `03_`, Edit series |
| Modular refactor (code review of 8 Oct), phases 0–7 | Agreed 8 Oct. Plan: "HomeTunes Modular Refactor Plan" (https://claude.ai/artifact/KGaAEeyJAo8kDyWDTmFYzD). Phases 0–3 merged into `main` (8–9 Oct, each after the user tried a test build) and Phases 1–3 released together as **v0.1.77** (9 Oct; the user: "Everything looks good"). Phase 4 (audio engine layer) merged into `main` and released on its own as **v0.1.78** (9 Oct; the user tried the test build: "All seems good"). Phase 5 (`VideoSession` out of the video page) merged into `main` and released as **v0.1.79** (9 Oct; the user tried the test build: "Things look good here"). Phase 6 (screen-file splits and shared widgets) is done on `refactor/p6-screens` (9 Oct), waiting for the user to try a test build; it will be released as 0.1.80. Phases 1–3 are released together as 0.1.77; new features wait until Phase 3 is done. See "Modular refactor" below |
| L: Linux build, incl. Steam Deck (0.2.0, the start of the next level) | On hold (6 Oct, the user's choice): WSL2 can't be installed on the current PC, so L1 (the Linux build) moves to another PC. Paused 1 Oct (the user's choice). Its only commit (the Linux notes) is on `main`; `feature/linux` was deleted. See "Platforms plan" below |
| A: Android Auto (the 0.2.x after L) | After L |
| T: Android TV (the 0.2.x after A) | After A |
| D: offline copies of server songs (was phase 4) | After the server review |
| E: audiobook server (Audiobookshelf) | New 25 Sep. Needs a plan. The order relative to D isn't decided |

### Modular refactor (agreed 8 Oct)
A code review of 0.1.76 (8 Oct; about 40,300 lines in `lib/`) found systems that would be better split into modules. The
plan is the artifact "HomeTunes Modular Refactor Plan" (https://claude.ai/artifact/KGaAEeyJAo8kDyWDTmFYzD), in eight
phases, each on its own branch (`refactor/p<n>-<name>`), merged with `--no-ff` once the user has checked it.
- **The rule (the user, 8 Oct):** nothing about how the user uses the app changes: same screens, menus, wording,
  gestures and settings search. `settings.json`, the other data files and `.htbackup` backups stay compatible. The
  only intended visible change is the Phase 1 video equaliser fix.
- **Phases:** 0 safety nets (settings and backup round-trip tests, a preview-picture baseline in `C:\Temp\ht\baseline`,
  player behaviour notes from the engine benches); 1 small fixes (video equaliser ignores the sample rate, the lyrics
  cache is emptied on every `LibraryModel` change, lyrics not dropped when missing songs are forgotten, the two
  `ownerFolder`s differ); 2 shared pieces (one sleep-timer core, `media_folders.dart`, a mixed-value helper for
  `--:--`, one interface for following moved / forgotten ids); 3 settings out of `LibraryModel` (one `Setting`
  description per value, settings groups as their own notifiers, the old names kept working, `ServerConnection`,
  `CustomArtStore`); 4 audio engine layer (`AudioEngine` interface + fake for tests, one shared audio chain, one
  engine factory); 5 `VideoSession` out of the video page; 6 screen-file splits and shared widgets; 7 docs and a
  layer-import test.
- **Decisions (the user, 8 Oct):**
  - Merge and release 0.1.71–0.1.76 first. Done: v0.1.76.
  - No release until Phase 3 is done. Phases 1–3 go out together as 0.1.77; each later phase is its own release.
    New features wait until Phase 3 is done.
  - Screens may import read-only lookup services (cover search, MusicBrainz, LRCLIB, Open Library, the update
    check), never the engine, file-writing or storage services. The Phase 7 layer test enforces it.
  - The shared filter description (Phase 6, step 6) is skipped unless a new tab with filters is planned.
- **Phase 0 (merged into `main` 8 Oct):**
  - `test/refactor_safety_test.dart`: `settings.json` saved back exactly as loaded (`test/fixtures/settings_full.json`
    changes every setting, and the test fails if a setting is missing from it), a 0.1.20-era settings file loading to
    the same values (its password moved to protected storage), and a backup holding every data file and cover
    restored ("replace") into a new app folder unchanged, apart from app paths moving to the new folder.
  - `tool\compare_previews.ps1`: 37 preview pictures compared byte for byte with `C:\Temp\ht\baseline` (made from
    `main` at v0.1.76). To make that possible: the previews now draw from fixed data folders
    (`C:\Temp\ht\preview-data\<name>`, the random temp folder's name showed in Settings and Videos), the Videos
    preview saves its two places a moment apart (they swapped in Continue watching), `poster_preview_test` takes
    `OUT`, and `theme_preview_test` (broken since 0.1.40: Settings needs `VideoLibraryModel`) draws again.
  - Real engine on the v0.1.76 build (the "before" for Phase 4): `engine_test` 3/3 (equaliser presets play at
    44.1 and 22.05 kHz, speed) and `player_gapless_test` 1/1 (in order, nothing skipped, Play next, repeat-one,
    a missing file skipped) passed. Logs: `C:\Temp\ht\bench-engine.log`, `bench-gapless.log`. The video player's
    equaliser has no bench yet; Phase 1 starts by checking it at 22.05 / 24 kHz.
- **Phase 1 (merged into `main` 8 Oct, after a test build):** tests in `test/refactor_fixes_test.dart`, each checked to fail
  on the old code.
  - Video equaliser: confirmed on the real engine first. At 22.05 kHz the video player sent the 16 kHz band, ffmpeg
    said "Parsed_equalizer_9: Invalid frequency and/or width!" and the equaliser stopped while the sound played on
    (24 and 44.1 kHz were fine). The video page now follows the sound's `audioParams` sample rate and builds its
    filter with `videoEqualizerSettings` (in `video_player_screen.dart`: `eqFilter` with the rate, plus the level
    for `replaygain-fallback`), and finishes one change before sending the next, like `PlayerModel`. New bench:
    `engine_test.dart` "the video player's equaliser at 22050 Hz has no rejected bands". Not done on purpose:
    calling `EqualizerModel.reportUnavailable` from the video player, as that flag is the music player's (the
    Equaliser screen's notice); Phase 4's shared audio chain decides how both report it.
  - `LyricsModel` reads songs' own lyrics again only when `library.tracks` is a new list (a rebuild: rescan,
    edits, written tags), not on every `LibraryModel` change (a theme or sidebar change used to empty the cache).
  - Forgetting missing songs also drops their online lyrics and "nothing found" times (`LyricsModel.removeIds`,
    added to `onIdsForgotten` in `main.dart`).
  - `VideoLibraryModel.ownerFolder` picks the deepest folder by folder count (`splitPath`), like
    `LibraryModel.ownerFolder`; it compared text length, which a path ending in several separators could fool.
- **Phase 2 (merged into `main` 8 Oct):** four shared pieces, every existing test passing unchanged; new
  tests in `test/refactor_shared_test.dart`. All in `lib/state/` (the folder rules use `isInside` / `splitPath`
  from `book_index.dart`, so `services/` would have broken the layer rules; the plan said `services/`).
  - `sleep_countdown.dart`: `SleepCountdown<M>` holds the ticking (4 a second), the fade, pausing and putting the
    volume back. `SleepTimer` and `VideoSleepTimer` keep their names, constructors and public members; each only
    gives its stopping point (`computeRemaining`), how to pause (`stopPlayback`) and the volume it fades. The
    video one also stops when its page closes (`beforeTick`, `canRestoreVolume`). `now` is no longer marked
    test-only (the timers read it).
  - `media_folders.dart`: `fileFormatOf`, `owningFolder`, `formatCounts`, `folderCheckTimeout`, `canListFolder`,
    `checkFolders` (reachable / offline). `LibraryModel` and `VideoLibraryModel` call them; `LibraryModel.formatOf`,
    `ownerFolder`, `formatsIn` and `folderReachable` stay as they were for callers and tests.
  - `mixed_value.dart`: `differentMarker` and `sharedValue` (the value every item shares, or `differ`), used by
    the song / album, book, video and collection editors. `edit_details.dart` re-exports `differentMarker`.
    The user chose (8 Oct) to make the video and collection editors match the others: `--:--` only where the
    items differ; boxes they all leave blank are plain (blank and missing count the same). Test in
    `video_sub_seasons_test.dart`.
  - `song_id_follower.dart`: `SongIdFollower` (`referencedIds`, `remapIds`, `removeIds`), implemented by
    playlists, listening places, bookmarks and lyrics (lyrics return no `referencedIds`: they don't keep a
    missing song), and `connectSongIdFollowers` in `main.dart` instead of the three hand-written lists.
  - Also: `test/video_pictures_test.dart` waits 100 ms before deleting its folder (as other Storage tests do). Its
    poster test failed 2 times in 5 under load (the whole suite, or two runs at once: "being used by another
    process" in tearDown); alone it passed 6 of 6 on both `main` and the branch, so it was a test race, not the code.
- **Phase 3 (merged into `main` 9 Oct; released with Phases 1–2 as v0.1.77):** `LibraryModel` 2,125 → about 1,590 lines. Every existing test
  passes unchanged (641), including the Phase 0 settings / backup round trips, and the preview pictures match.
  - 3a: `state/settings/setting.dart` (`Setting`: key, default, read, write; `SettingsReader`, LibraryModel's old
    `_Fields`) and `state/settings/settings_groups.dart`: `FolderSettings`, `ServerSettings`, `OnlineSettings`,
    `PlaybackSettings`, `ListeningSettings`, `VideoSettings`, `AppearanceSettings`, `LayoutSettings`, and
    `AppSettings` (reset / load / toJson). `LibraryModel.settings` holds them; its old setting names pass straight
    through (getters and setters), so screens and tests didn't change. `ReplayGainMode` moved there (still
    exported from `library_model.dart`). Keys in settings.json may now be in a different order (group by group);
    the values are the same, and nothing depends on the order.
  - 3b: the simple setters (themes, look, online lookups, playback, listening, video, sidebar, artists grid, quick
    links) live in their group (`commit()`: redraw then save, as before; `setBookCoversTall` saves first, as
    before); `LibraryModel`'s methods keep their names and pass through. Setters that change the library itself
    (folders, file types, book genres, Move to Books, server books, video folders, artist / series pictures,
    Edit series) stay in `LibraryModel`. `state/server_connection.dart` (`ServerConnection`: the password in
    protected storage, the Subsonic client and its cover cache, trying an address https-then-http with the
    plain-http question); `state/custom_art_store.dart` (`CustomArtStore`: chosen pictures stored by md5 and
    tidied, for covers / artist / series pictures with the 30-minute protection, and for video pictures without
    it, as before; `picturesChanged`, set in `main.dart` to clear Flutter's image cache). `LibraryModel.coverSource`
    / `artistSource` say where a picture comes from; `ui/widgets/library_images.dart` (`LibraryImages`) turns that
    into images under the old names (`lib.artFor`, `lib.artistImage`). `state/` no longer imports Flutter's
    painting library. The groups are also provided on their own in `main.dart`.
  - Not done on purpose (the user to decide): every settings change still redraws whatever watches
    `LibraryModel`, as before. Switching screens over to watch only their group, then stopping those redraws,
    touches about 40 widgets and could leave one that no longer updates; the gain is small (settings change
    rarely). The groups are ready for it. Also not reached: `LibraryModel` under 1,000 lines (library, edits,
    scanning, server sync, backup, tag writing and artist / series pictures remain).
- **Phase 4 (merged into `main` 9 Oct after the user's test build, released as v0.1.78):** nothing the user sees changes.
  `flutter analyze` clean, 663 tests pass, real engine: `engine_test` 4/4, `player_gapless_test` 1/1,
  `video_probe_engine_test`, `video_engine_test` and `video_bar_engine_test` pass.
  - 4.1: `services/engine/audio_engine.dart` (`AudioEngine`: the streams, state and actions `PlayerModel` uses, plus
    `hasOptions` / `setOption` for mpv properties, which throws when refused) and `media_kit_audio_engine.dart` (a
    one-for-one pass-through to media_kit). `PlayerModel(..., engine:)` takes one; the app gives none (media_kit).
  - 4.2: `test/fake_audio_engine.dart` (records every call; `finishCurrent`, `reportDuration`, `reportSampleRate`,
    `reportError`) and `test/player_model_test.dart` (13 tests: gapless hand-over and end of queue, Play next,
    repeat-one, gapless off, a missing file skipped, a book skip across files, Back to music, the equaliser at 22.05
    and 48 kHz, a refused equaliser, the volume scale, a stuck song reopened, a learned length applied).
  - 4.3: `services/engine/audio_chain.dart` (`AudioChain`): the equaliser steps the music player and the video page
    each had their own copy of (filter for the sample rate, sent only when changed, one send at a time then the
    latest). `EqLevel.volumeFactor` (music: the volume is turned down) or `replayGainFallback` (videos). The music
    player still tells the Equaliser screen about a refusal (`onResult`); the video page only logs it, as before.
    `videoEqualizerSettings` stays and calls `AudioChain.settingsFor`. Tests: `test/audio_chain_test.dart`.
  - 4.4: `services/engine/engines.dart`: `createEngine(EngineUse)` (video page, music video, frame picker, probe,
    thumbnails; each keeps its title, and the video page keeps libass off on Android), `prepareEngine` (each use's
    fixed mpv settings, the same as before; `engineSettings` lists them) and `Mpv` (mpv properties and commands,
    null when the engine isn't mpv). No file in `ui/` uses `NativePlayer`, `setProperty` or `PlayerConfiguration` any
    more; `video_probe`, `video_thumbnails` and `video_stats` go through it too. **Deviation from the plan's Phase 7
    rule, agreed in the plan:** the video page, music video and frame picker still create their player (through
    `engines.dart`), because media_kit's `Video` widget needs it; Phase 5 (`VideoSession`) moves the video page's.
  - 4.5: `PlayerModel` was not split further (optional in the plan): it stays one file, now without the equaliser code.
  - Found while testing (not changed, as the phase changes no behaviour): a song whose file has gone is skipped, but
    its "isn't on this device – skipped" message is cleared as soon as the next song opens, so it never shows.
    `player_model_test` records today's behaviour; a small fix for a later release if the user wants it.
  - `tool/bench/frame_picker_engine_test.dart`'s frame step doesn't move on this PC with any video, on v0.1.77 as
    well as on the branch (the bench uses media_kit directly, none of the app's code). The video benches need
    `--dart-define=VIDEO=` a video over 60 s (they seek to 42.5 s and 60 s); `C:\Temp\ht\videobenches.cmd` runs them.
- **Phase 5 (merged into `main` 9 Oct after the user's test build, released as v0.1.79):** nothing the user sees
  changes. The video page (`ui/screens/video_player_screen.dart`, 1,311 → 915 lines; its page state about 530, all
  layout and controls) only draws now.
  - `services/engine/video_engine.dart`: `VideoEngine` (what a video page needs from its player: the streams, the
    tracks as `MediaTrack`, open / play / seek / speed / volume / tracks, mpv options and commands, a screenshot) and
    `MediaKitVideoEngine` (the media_kit player, made with `createEngine(EngineUse.videoPage)`; `player` is still
    used by the page's `Video` widget, wheel and volume bar).
  - `state/video_session.dart`: `VideoSession` (a `ChangeNotifier`, one per open page) runs everything the page's
    state used to: opening (place, rewind after a break, the collection's speed, "Carrying on from" through
    `onCarryOn`), previous / next and `shownId` (0.1.71), Up next, the remembered audio / subtitle choice (subtitle
    files added with `sub-add`), saving the place (every 5 s, on pause, at the end, when the page closes), the
    videos' equaliser (`AudioChain`), the volume boost's top, pausing / being paused by the music, `NowWatching`
    and the playback stats. `VideoEngineTransport` there replaces `MediaKitTransport` (it implements `state/`'s
    `VideoTransport`, so it lives in `state/`, not `services/engine/` as the plan said).
  - `state/video_tracks.dart`: `languageName`, `languageCodeFor`, `trackLabel`, `matchTrack`, moved unchanged; the
    page still exports the first three (and `videoEqualizerSettings`) for older callers and tests.
  - Tests: `test/fake_video_engine.dart` and `test/video_session_test.dart` (10: speed, carrying on and Start over,
    the end and Up next, Cancel and the last episode, previous / next across seasons and twice in a row (0.1.71),
    places on pause and on close, remembered tracks, a file that can't be opened, music pausing the video, speed for
    the collection). 673 tests in all.
  - Found (not changed, as the phase changes no behaviour): two previous / next presses in the very same instant
    can open in the wrong order (the second skips the equaliser wait and opens first). It was the same before;
    a person can't press that fast.
- **Phase 6 (branch `refactor/p6-screens`, 9 Oct; waiting for the user's test build):** nothing the user sees
  changes; every step kept the 37 preview pictures identical. No file in `lib/ui/` is over 600 lines now (the
  biggest is `widgets/music_video_view.dart`, 591; before: 7 files over 600, the biggest 1,401).
  - How files were split: code moved as it was. Pieces that stand alone became their own libraries, exported from
    the file they came from so no importer changed; pieces tied to a screen's private classes became Dart `part`
    files (same library, so nothing was renamed). Where one big `State` class had to be cut, methods that don't
    call `setState` moved to a part file as a private extension on that state.
  - `video_collection_screen.dart` (1,401 → 334, the page): parts `video_collection/collection_card.dart`,
    `contents_panel.dart`, `episode_list.dart` (rows, headings, the select-mode mixin); libraries
    `video_collection/edit_collection.dart` and `season_title_dialog.dart`.
  - `videos_screen.dart` (937 → 578): `widgets/video_card.dart` (`VideoCard`, `showVideoMenu`, card sizes,
    `videoLength`), `widgets/video_group_menu.dart` (`showVideoGroupMenu`), `widgets/video_selection_bar.dart`.
  - `video_player_screen.dart` (915 → 569): parts `video_player/video_controls.dart` (the controls, keys, Speed and
    Audio and subtitles dialogs, Use this frame) and `video_player/video_bar_volume.dart`.
  - `settings/appearance_settings.dart` (868 → 477): library `settings/appearance/colour_picker.dart`
    (`showColourPicker`, `PickerMode`), part `settings/appearance/theme_editor.dart`.
  - `settings/server_settings.dart` (741 → 392): part `settings/servers/server_dialog.dart`.
  - `edit_details.dart` (702 → 550): part `edit_details/saving.dart` (`_saveChanges`, `_resetAll`).
  - `video_pictures.dart` (645 → 428): library `video_pictures/frame_picker.dart` (`showFramePicker`).
  - Shared widgets: `widgets/selection_bar.dart` (`SelectionBar`: the songs bar, the albums / audiobooks bar and
    `VideoSelectionBar` each pass their own buttons; padding, side insets and one-line label kept per bar);
    `widgets/picture_choice.dart` (`showPictureChoices`, `PictureChoice`: video picture, collection poster,
    series and artist pictures, each with its own choices, wording and keys; the playlist icon picker and the two
    cover grids do different jobs and stay as they were); `widgets/mixed_value_field.dart`
    (`mixedValueDecoration`: the `--:--` box with its helper line and "keep each one's own" button, used by the
    song / album and book editors; the video and collection editors only show a plain `--:--` hint, so moving them
    over would change how they look).
  - Not done, as agreed: one way of describing filters (step 6).
  - **Fix on the same branch (9 Oct, the user found it while testing):** Find cover online found nothing for Black
    Eyed Peas' "THE E.N.D.". Two causes, neither from the refactor. (1) MusicBrainz titles it "The E•N•D", and a
    quoted search for "E.N.D." never matches; now, when the exact search finds nothing, `CoverSearch` searches again
    without punctuation (`CoverSearch.loosen`: letters, digits and spaces in any alphabet), only if that changes
    the names. (2) The Cover Art Archive (archive.org) took 16.5 s for that cover's preview, past the 15 s limit,
    and late previews were silently dropped, so a slow day looked like "no covers found" for every album. Now
    45 s for a preview (`previewWait`) and 60 s for the full picture, and when MusicBrainz finds albums but no
    picture arrives (timeouts or errors, not a 404 "no cover") the dialog says the cover website didn't answer
    in time (`CoverSiteUnavailable`). A busy MusicBrainz (503) is asked again twice, not once. Checked live: the
    album is found with its cover in about 12 s. Tests: `test/cover_search_test.dart`.

### Platforms plan: Linux, Android Auto, Android TV (agreed 1 Oct)
(Versions, corrected 7 Oct by the user: **0.2.0 is only for the next level of development**. Fixes and features on the app as it is stay on 0.1.x (the Next-video fix is 0.1.71). The 6 Oct note said the next release would be 0.2.0 whatever it held; that was wrong, and a 0.2.0 test build of the fix was renumbered 0.1.71. The platform phases start the 0.2.x line: Linux **0.2.0**, Android Auto **0.2.1** and Android TV **0.2.2**; 0.1.x work in between doesn't move them. The build number after `+` keeps counting up from 72, so phones still accept each update. The plan doc matches this. Before 6 Oct the phases were renumbered each time other 0.1.x work went first, ending at 0.1.71–0.1.73.)
The plan is the doc "HomeTunes Platforms Plan" (https://claude.ai/code/artifact/831e2a97-57ac-4af8-b0fd-738442c570d9),
with numbered steps per phase (L1–L7, A1–A7, T1–T7). Agreed order: **L Linux → A Android Auto → T Android TV**, each
on its own branch (`feature/linux`, `feature/android-auto`, `feature/android-tv`) and released on its own.
- **User's answers (1 Oct):**
  - Linux: as accessible as possible and must run on the user's **Steam Deck** (Desktop and Game Mode). AppImage
    first (bundles libmpv, so the LGPL source offer applies as on Windows), then Flatpak (Flathub / Discover), plus a
    tarball. Built **locally on the PC under WSL2**; a GitHub Actions job is the acceptable backup.
  - Car: **2018 Ford Focus (SYNC 3)**, Android Auto by USB cable. Wireless must work too; SYNC 3 is wired-only, so
    that means a wireless Android Auto adapter (no separate app code). Sideloaded app needs Android Auto's
    developer setting "Unknown sources".
  - TV: **Sony "BRAVIA 4K GB ATV3"** (Android TV, not Google TV; probably Android 8/9, likely 32-bit ARM, so check
    `armeabi-v7a` in the APK). Music from **both USB drives and the server**.
- **Key findings:** about 10 Windows-only calls in `lib/` (`rundll32`/`explorer` in update_checker, book_screen,
  details_screen, videos_screen, video_player_screen, about_settings; `main.dart` and `media_session.dart` skip
  Linux) go behind one `services/desktop_open.dart`. Linux media controls via `audio_service_mpris` (0.2.1; no seek
  signals, volume or shuffle). The manifest already declares audio_service's `MediaBrowserService`; Android Auto
  needs `automotive_app_desc.xml`, a browse tree (`getChildren`/`playFromMediaId`/`playFromSearch`), a cold-start
  check and maybe a `ContentProvider` for covers. The D-pad focus work (T3) is started in L6 for the Steam Deck's
  controller.
- **New since the plan (checked 6 Oct on 0.1.70):** Always on top (`services/window_pin.dart`, 0.1.60) is Windows
  only. On Linux, `linux/runner/my_application.cc` needs to answer the same `hometunes/window` channel with GTK's
  keep-above setting (L2 in the plan doc). The other Windows-only calls are unchanged; only their line numbers moved.
- Model/Android version of the TV still to confirm (Settings › Device Preferences › About), optional.

### E: Audiobook server (asked for 25 Sep)
- **User's answer:** books should come from **both** the music server and, optionally, a separate
  audiobook server.
- **Server software the user runs or plans to run:** Navidrome, Audiobookshelf, and Jellyfin/Plex.
- **What's already there:** Settings › Servers has an "Audiobooks from the music server" switch
  (`LibraryModel.serverBooks`, default on) and a greyed-out "Audiobook server" block (server type,
  address, username, password, Connect) under a "coming in a later update" notice. It's
  `_AudiobookServerPreview` in `server_settings.dart`, and phase E makes it work.
- **Plan needed:**
  - An Audiobookshelf client (API-token login, libraries, items, chapters, covers, streaming, and
    maybe syncing listening progress with ABS).
  - Where it sits in Settings › Servers: since 0.1.46 an Audiobookshelf server can already be
    added, tested and ticked for audiobooks there (`ServerType.audiobookshelf`, `ServersModel`);
    phase E makes it stream (see `03_…` → Servers page → "Next, when a server type is built").
  - How ABS books join `groupBooks`.
  - Jellyfin/Plex later.

### D: Offline server songs
- **Needs first:** the server review (below), including whether the Navidrome server can transcode.
- **Downloading:** download a song, album, playlist or Liked Songs. A "Keep offline" option
  follows albums and playlists. The quality is either the original or a server-converted copy.
- **Downloads screen:** progress, pause/retry, space used, delete.
- **Playback:** a downloaded copy plays first. Offline mode happens automatically when the server
  can't be reached.
- **Phone:** Wi-Fi-only, a storage limit, and downloads that continue in the background.
- **Backups:** list what's kept offline, but not the files themselves.
- **Open questions (ask when we get there):** the quality choice, and whether to add crossfade
  (it would need two players).

## Needs reviewing with the user (when needed)
- **Server review (partly answered 25 Sep):**
  - The user runs or plans Navidrome, Audiobookshelf, and Jellyfin/Plex.
  - How audiobooks on the server should work: `bookKey` for server files uses album + author.
  - Whether the server can transcode.
- **Android and sidecar files:** the app only asks for the media permission (`READ_MEDIA_AUDIO`),
  which hides jpg/json/txt/pdf. Options are an opt-in "All files access"
  (MANAGE_EXTERNAL_STORAGE, fine for sideloading) or leaving it as is.

## Security
A security review of 0.1.20 on 28 Sep found 3 medium and 7 low issues. All ten were fixed in 0.1.21
and released as v0.1.21 on 28 Sep. The plan was the artifact "HomeTunes Security Fix Plan"
(https://claude.ai/artifact/PBV5TRiFopdA2mimDTAkLi); the user took the recommended option each
time. What each fix does is in `05_CODE_GUIDE.md` → "Fixed in 0.1.21", and the code comments say
"security review #n".
- **Release key:** release APKs are signed with HomeTunes' own key (`CN=James Miller`, SHA-256
  `758f6618fcb4b2832114d53b7ec887d03cfa4d923976ff602a2988d2c0ff1030`), not the debug key. The key is at
  `C:\Users\James.Miller\keys\hometunes-release.jks` and is read through `android/key.properties`,
  which is never committed. **Never read or print either.** The build refuses a release APK without
  it, and `publish_release.ps1` refuses a debug-signed APK. Changing the key again would force every
  phone to uninstall and restore.
- **Accepted as they are:**
  - `usesCleartextTraffic` stays on, because home-network servers need http. Plain http to an
    internet server is only used after the user agrees once for that server (`httpAllowedHost`).
  - The Windows build isn't code-signed (no paid certificate); SHA-256 checksums are published
    with every release instead.
  - The playback engine (media_kit's libmpv/FFmpeg) parses untrusted media. On 28 Sep its
    libraries were already the newest available. Recheck with `flutter pub outdated` now and then.
- **Not covered by the review (possible future work):** `MainActivity.kt`, the iOS and Linux
  runners, most of the vendored tag parsers (only skimmed), and any testing by running the app.

## Known issues / small things
- **Lock-screen playback stopping:** fixed in 0.1.20 and confirmed by the user. If it ever comes
  back, ask for Settings › About › Playback log.
- **Probable bugs still open** (found while commenting the code, not fixed; see `05_CODE_GUIDE.md`
  → "Things spotted while commenting"): non-Latin titles break MusicBrainz track-number matching
  (`normalizeTitle` keeps only a–z and 0–9), and plain `.aac` files are treated as writable like
  M4A. The others from that list were fixed in 0.1.16.
- **VS Code F5 debug run on Windows can close after the scan.** Release is fine. This is parked.
- **Some tags are rewritten by the library, not preserved:**
  - The patched ID3 writer rewrites `TLEN` from the parsed duration, which may be slightly off for
    short files.
  - The FLAC vendor string is emptied.
  - Neither matters for playback.
- **iOS:** there's no local folder access, only server streaming. (Since 0.1.17 the server
  password is kept in the Keychain, not in the settings file.)
- **Music videos (branch `feature/music-videos`) — before releasing 0.1.40:**
  - **Done 1 Oct (licences for the video engine):** read from the shipped files themselves (FFmpeg and mpv record their build settings): Windows `libmpv-2.dll` = mpv 652a1dd9 (`-Dgpl=false`), FFmpeg n6.0 (`--disable-gpl --disable-nonfree`, every part "LGPL version 3 or later"), matching media-kit/libmpv-win32-video-build's recipe at commit 87bb9596; Android `libmpv.so` = libmpv-android-video-build v1.1.7 "default" (FFmpeg n6.0 LGPL 3, mpv 78d43740 `-Dgpl=false`, libass 0.17.1, HarfBuzz 7.2.0, FriBidi 1.0.12, FreeType 2.13.0, Mbed TLS 3.4.0, dav1d 1.2.0, libxml2 2.10.3). No LZO (GPL) in the DLL. LGPL parts: mpv, FFmpeg, FriBidi, and on Windows libsoxr, GNU libiconv 1.17, uchardet (tri-licence, used under the LGPL); their source is in `HomeTunes-audio-engine-source.zip` (`tool/engine_source.ps1`; libsoxr / uchardet have no recorded commit, so the recipe's source and the nearest release are both in it). The permissive libraries (33, incl. the ANGLE / SwiftShader / Vulkan / zlib DLLs next to the exe) are in `licenses/ENGINE-COMPONENTS.txt` with their licence texts (fetched from each project's repository; fontconfig's from a GitHub copy because freedesktop's GitLab blocks scripts), shown in the app's Licences page as "Playback engine: other libraries". `THIRD_PARTY_NOTICES.md` updated, plus the `image` package.
  - A Windows build folder that ever held the audio engine keeps it: CMake skips unpacking the video archive while `build\windows\x64\libmpv\` isn't empty. Delete that folder (and the stale `media_kit_libs_windows_audio_plugin.dll` in the Release folder) once, or `build_release.ps1` ships the old audio-only DLL and videos never show.
  - Not yet tried on the phone (APK size and 4K VP9 decoding speed on the Pixel 8 are worth checking).
  - Ideas not done: a small video in the desktop player bar or mini player; a "Music video" row on the Details page.
  - Videos tab, not tried yet: on the phone (the new "Photos and videos" permission, full screen turning the phone sideways, thumbnail speed), and the full-screen buttons on a real window (checked with tests and the engine bench only; the preview pictures can't draw the video engine).
  - Collections, audio / subtitle choice and .nfo files (same branch): mpv drawing subtitles (`libass: true` on Windows) was checked on the real engine for track switching but not yet looked at in the app window (ASS styling, DVD picture subtitles on Claymore). On Android only text subtitles show (Flutter subtitle view); picture / styled ones would need libass there too. Writing details inside MKV / MP4 files themselves was left out on purpose (multi-GB rewrites); .nfo files are written instead. Ideas: a "Save all edits into .nfo files" button in Settings like the music one; reading `movie.nfo` for single-film folders; posters from .nfo `<thumb>` links.
  - Video player look (Settings › Appearance › Video player, same branch): checked with tests and the Settings preview only; the real controls over a real video (glow / circles, sizes, full screen, phone) not yet seen in a window. Play/pause is media_kit's animated icon, which takes the halo but not the icon shadow. The seek bar itself has no backing (its unplayed part follows the button colour instead).
  - Video in the bottom bar / media keys and scroll to skip (30 Sep): checked with tests (fake players) only; the real Windows media overlay and keyboard play/pause key with a video, and the wheel over media_kit's progress bar (its position is worked out from media_kit 2.0.1's layout, `videoSeekBarBand`) not yet tried in a window. **Fixed (30 Sep):** blank buttons on the video player (skip back / forward, speed, subtitles, and 13 more icons in the video screens) were icons left out of the release build's icon font by Flutter's icon tree shaker (3.47.5; it missed those files' icons, cause not pinned down). `build_release.ps1` now builds with `--no-tree-shake-icons` (+~1.6 MB) and runs `tool\check_icons.py`, which fails the build if any `Icons.x` used in lib\ or media_kit's controls is missing from the built font. If tree shaking is ever turned back on, keep the check.
  - Season titles and "Play music videos automatically" (same branch): not yet tried on the real F:\Videos library / a real music video; Now Playing's video button choice lasts for the song only (not remembered).
  - Chosen pictures / posters (same branch): the Pick a frame dialog's engine steps were checked with `tool/bench/frame_picker_engine_test.dart`, but the dialog itself (the moving picture in it) not yet in a real window. Search online was checked live (`tool/probe_video_art.dart`: Silo, Mickey 17, Claymore). Ideas: TMDB / fanart.tv as extra sources if the user adds their own free API key; writing a chosen poster as `poster.jpg` into the collection's folder (alongside the .nfo option) so other apps see it.

## Source control
`main` is **0.1.79+81** and the latest release is **v0.1.79** (9 Oct: refactor Phase 5, the video session, with no
visible changes). Before it, **v0.1.78** (9 Oct: refactor Phase 4, the audio engine layer) and **v0.1.77** (9 Oct: refactor Phases 1–3; the visible changes
are the video equaliser at 22 kHz and `--:--` in the video / collection editors). Work on the app as it is stays
0.1.x (0.1.80 next, refactor Phase 6); 0.2.0 is kept for the next level of development (the user, 7 Oct; see the
Platforms plan above). Open besides `main`: `refactor/p6-screens` (Phase 6, waiting for the user's check). Refactor branches are `refactor/p<n>-<name>` (see
"Modular refactor" above). Each feature gets its own branch, merged into `main` with
`--no-ff` once the user approves, and merged branches are deleted. Builds (`build\dist`) are not in
git; they are rebuilt from source with the commands in `02_…` and published as GitHub Releases. The
repo copy of these notes (`docs/ai-context/`) is kept the same as the project copy.
