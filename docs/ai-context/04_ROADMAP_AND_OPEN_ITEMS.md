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
| L: Linux build, incl. Steam Deck (0.1.59) | Paused 1 Oct (the user's choice). Its only commit (the Linux notes) is on `main`; `feature/linux` was deleted. See "Platforms plan" below |
| A: Android Auto (0.1.60) | After L |
| T: Android TV (0.1.61) | After A |
| D: offline copies of server songs (was phase 4) | After the server review |
| E: audiobook server (Audiobookshelf) | New 25 Sep. Needs a plan. The order relative to D isn't decided |

### Platforms plan: Linux, Android Auto, Android TV (agreed 1 Oct)
(Versions moved up by one on 1 Oct, the user's choice: 0.1.41 went to selectable titles, video search and window scaling, so Linux is 0.1.42, Android Auto 0.1.43 and Android TV 0.1.44. The plan doc was updated to match. Moved up by one again later on 1 Oct: Linux was paused and 0.1.42 went to the video loading page, so Linux was 0.1.43, Android Auto 0.1.44 and Android TV 0.1.45. And once more the same day: 0.1.43 went to the bottom bar fix, so Linux was 0.1.44. Then 0.1.44 went to video Details, and 0.1.45 / 0.1.46 to the Home revamp and the Servers page (the user chose two updates), so Linux was 0.1.47. Then 0.1.47 went to Shift + click selection (2 Oct), so Linux was 0.1.48. Then 0.1.48 went to Esc cancelling a selection (2 Oct), so Linux was 0.1.49. Then 0.1.49 went to the search box in the filter drop-downs (2 Oct), so Linux was 0.1.50. Then 0.1.50 went to the no-internet warning (2 Oct), so Linux was 0.1.51. Then 0.1.51 went to the update check at every start (2 Oct), so Linux was 0.1.52. Then 0.1.52 went to the Artists tab's list / grid (2 Oct), so Linux was 0.1.53. Then 0.1.53 went to artist pictures (2 Oct), so Linux was 0.1.54. Then 0.1.54 went to the one-song album fix (3 Oct), so Linux was 0.1.55. Then 0.1.55 went to video playback stats (5 Oct), so Linux was 0.1.56. Then 0.1.56 went to smoother music videos (5 Oct), so Linux was 0.1.57. Then 0.1.57 went to smoother video drawing on phones (5 Oct), so Linux was 0.1.58. Then 0.1.58 went to the music video drawing fix (5 Oct), so Linux is now **0.1.59**, Android Auto **0.1.60** and Android TV **0.1.61**. Each new piece of work while Linux is paused takes the next number and moves these up. The plan doc may still show older numbers.)
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
`main` is **0.1.44+44** and the latest release is **v0.1.44** (1 Oct; v0.1.40, the videos
release, and v0.1.41 to v0.1.43 came out the same day). `feature/home-revamp` (0.1.45+45) and `feature/servers` (0.1.46+46, branched from it, so merge Home first) are waiting for the user's approval; there are no other branches (merged feature branches are deleted). Each feature gets its own branch, merged into `main` with
`--no-ff` once the user approves, and merged branches are deleted. Builds (`build\dist`) are not in
git; they are rebuilt from source with the commands in `02_…` and published as GitHub Releases. The
repo copy of these notes (`docs/ai-context/`) is kept the same as the project copy.
