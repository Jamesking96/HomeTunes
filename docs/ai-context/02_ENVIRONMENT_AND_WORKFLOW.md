# Environment and workflow

## Machines
- **User's Windows PC**:
  - Repo: `C:\Users\James.Miller\source\hometunes`
  - Flutter: `C:\Users\James.Miller\flutter\bin` (not always on PATH in fresh shells, so prepend it)
  - adb: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`
  - Test audiobooks: `F:\AudioBooks` (Libation M4Bs with `.metadata.json` + `.jpg` + some PDFs,
    Harry Potter MP3s with a collection `Info.txt`, Dune M4Bs with poor tags)
  - Test music: `F:\Music` (~2,000 files)
- **Phone**: Pixel 8, Android 17 (API 37), adb serial `43141FDJH002LV`. It isn't always plugged
  in; check with `adb devices`.
- **Earlier sessions** worked from a Linux cloud clone (no Flutter there) that pushed to GitHub.
  They then ran everything on the PC through Desktop Commander (`start_process`, PowerShell).
  If you have the same set-up, run Flutter work on the PC, not in the cloud.
- **VS Code** (`.vscode/launch.json`): launch configs "HomeTunes – Windows", "HomeTunes – Pixel 8"
  (debug and release, by the phone's serial) and a compound "Windows + Pixel 8".

## Platform folders
The platform folders (`windows/`, `android/`, `ios/`, `macos/`, `linux/`) were made by `flutter create`
and are **tracked in git**. `tool/patch_platforms.dart` applies HomeTunes' changes to them (Android
permissions and backup rules, the audio_service entries, `MainActivity`, `compileSdk = 37`, release
signing in `android/app/build.gradle.kts`, `keep.xml`, macOS entitlements, iOS `Info.plist`). It is
safe to re-run. For a copy without the platform folders (e.g. the source zip), `setup.ps1` (or
`setup.sh`) runs `flutter create --org com.hometunes`, then `patch_platforms.dart`, then
`flutter pub get`.

**Don't delete and regenerate them.** Two fixes live only in the tracked files, and the patcher
doesn't recreate them:
- `windows/runner/flutter_window.cpp`: `KeepAccessibilityOff`, the 0.1.19 fix for the Windows
  accessibility-bridge crash (start with `--screen-reader` to turn accessibility back on).
- `android/app/src/main/kotlin/.../MainActivity.kt`: the `openUrl` method (0.1.23) that the phone's
  "Open download page" uses. The patcher leaves an existing `MainActivity.kt` alone, and its
  template has no `openUrl`.

## Running long jobs on the PC
Tool calls time out after about 60 s. Start long jobs detached, with logs, then check on them:
```powershell
Start-Process -FilePath cmd.exe -ArgumentList '/c','set PATH=C:\Users\James.Miller\flutter\bin;%PATH% && flutter test > C:\Temp\ht\all.log 2>&1' -WorkingDirectory C:\Users\James.Miller\source\hometunes -WindowStyle Hidden
# later:
Get-Content C:\Temp\ht\all.log -Tail 5
```
`C:\Temp\ht` is the scratch folder. Kill leftover `flutter test` / `flutter_tester` processes
before re-running. An orphaned one once sat hung for hours.

## Before touching the PC
Check that the user isn't using the app or a debug session:
```powershell
Get-Process hometunes -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'flutter_tools.snapshot"? run|flutter.bat"? run|run --machine' }
```
If they are, don't build the Windows app (`LNK1168`), and don't switch branches under them.

## Verify a branch (the usual loop)
1. `git pull` on the PC. Git may show the generated plugin registrant files as changed; that's
   only line endings (`git add` clears it). Commit `pubspec.lock` whenever dependencies change.
2. `flutter pub get` (after pubspec changes), then `flutter analyze` (must be clean), then
   `flutter test` (all must pass).
3. Windows release: `powershell -ExecutionPolicy Bypass -File tool\build_release.ps1`. This makes
   `build\dist\HomeTunes-<ver>-windows.zip` and `HomeTunes-Setup-<ver>.exe` (Inno Setup 6,
   `installer\hometunes.iss`; never change its `AppId`). Both include the VC++ runtime DLLs,
   `LICENSE.txt`, `THIRD_PARTY_NOTICES.md` and `licenses\`. The version comes from `pubspec.yaml`.
   `-SkipBuild` repackages the last build; `-Android` also builds the APK (step 4).
4. APK: `tool\build_release.ps1 -Android` builds `build\dist\HomeTunes-<ver>-android.apk` and
   checks it's signed with the release key (see "Release signing" below). By hand, Gradle needs
   the first line or it fails with "Unable to establish loopback connection":
   ```powershell
   $env:JAVA_TOOL_OPTIONS="-Djdk.net.unixdomain.tmpdir=C:\Temp\ht"; $env:GRADLE_OPTS=$env:JAVA_TOOL_OPTIONS
   flutter build apk --release
   Copy-Item build\app\outputs\flutter-apk\app-release.apk build\dist\HomeTunes-<ver>-android.apk
   adb install -r build\dist\HomeTunes-<ver>-android.apk
   adb shell dumpsys package com.hometunes.hometunes | Select-String versionName,versionCode
   ```
   `INSTALL_FAILED_VERSION_DOWNGRADE` means you forgot to raise the `+build` number.
5. Real-engine checks, when playback logic changes (these live in `tool/bench/`, so the normal
   `flutter test` run skips them):
   ```
   flutter test tool/bench/engine_test.dart --dart-define=LIBMPV=C:\Users\James.Miller\source\hometunes\build\windows\x64\runner\Release\libmpv-2.dll
   flutter test tool/bench/player_gapless_test.dart --dart-define=LIBMPV=...same...
   ```
   Scan timing through `LibraryModel`: `flutter test tool/bench/library_scan_test.dart --dart-define=FOLDER=F:\Music`.
6. **Publishing builds for download (GitHub Releases, since 0.1.20):** once main is
   merged and pushed and the three files are in `build\dist`, run
   `powershell -ExecutionPolicy Bypass -File tool\publish_release.ps1 -NotesFile <notes.md>` on the
   PC (`-Version` overrides the version from `pubspec.yaml`). It tags `origin/main` as `v<version>`,
   creates the release and uploads the APK, the installer, the zip, the audio engine's source
   (`HomeTunes-audio-engine-source.zip`, made once by `tool/engine_source.ps1`; the LGPL asks for
   it; `tool/attach_engine_source.ps1` adds it to older releases) and the user guide. The release page shows "What's new" (the notes file: a few plain-English
   bullets) followed by the whole of `docs/USER_GUIDE.md` (download and install per device, first
   steps, everyday use, backups, troubleshooting), which is also attached as `HomeTunes-README.md`.
   Screenshots for the guide live in `docs/images/` (1600 px wide JPEGs; the script links them from
   `main`). **Blur any lyrics in screenshots** (the user's rule: never reproduce copyrighted lyrics).
   **Keep `docs/USER_GUIDE.md` up to date when features or menu names change.** `-UpdateOnly`
   refreshes just the page text and guide of an existing release; re-running without it
   skips files already uploaded.
   It refuses a debug-signed APK (and stops if it can't find apksigner), and writes
   `HomeTunes-<ver>-SHA256SUMS.txt` (uploaded, and listed at the end of the page). The app's
   "Check for updates" reads the latest release and checks the installer against that file, so
   only publish finished builds. It signs in with git's saved GitHub login (there's no `gh` on the
   PC) and never prints it. Builds are never
   committed to git. Downloads: https://github.com/Jamesking96/HomeTunes/releases
7. Probes (run with `dart run`):
   - `tool/probe_books.dart <folder or file> [max files]`: raw tags and chapters per file
   - `tool/probe_book_extras.dart <folder>`: books plus what came from sidecars
   - `tool/probe_library.dart <folder>`: grouping
   - `tool/probe_lyrics.dart "Title" "Artist" [secs]`: real LRCLIB lookup; prints what was found, not the lyrics
   - `tool/bench_scan.dart <folder> [files]`: scan speed

   Run with `flutter test`:
   - `tool/probe_update_test.dart`: live "Check for updates" against the real latest release
     (downloads the installer and checks its checksum; installs nothing)
   - Preview pictures, drawn off-screen to `C:\Temp\ht\preview` (or `--dart-define=OUT=<folder>`):
     `tool/theme_preview_test.dart` (Settings › Appearance in each theme), `ui_preview_test.dart`
     (0.1.26), `whats_new_preview_test.dart` (0.1.28), `theme_sharing_preview_test.dart` (0.1.29),
     `notice_close_preview_test.dart` (0.1.30). They use Windows' Segoe UI, so run them on the PC.

## Release signing (since 0.1.21)
- Release APKs are signed with HomeTunes' own key, `CN=James Miller`, SHA-256
  `758f6618fcb4b2832114d53b7ec887d03cfa4d923976ff602a2988d2c0ff1030`.
- The key is at `C:\Users\James.Miller\keys\hometunes-release.jks`, outside the repo.
  `android/key.properties` points at it. It is gitignored (by the `android/.gitignore` that
  `flutter create` makes, not the root `.gitignore`); never commit it. The user keeps the key and
  its password in their password manager plus an offline copy.
- **Never read or print `key.properties` or the key.**
- The signing set-up in `android/app/build.gradle.kts` comes from `patch_platforms.dart`. Gradle
  stops a release build if `key.properties` is missing, and `build_release.ps1 -Android` and
  `publish_release.ps1` both refuse a debug-signed APK.
- Keep the same key for ever: an APK signed with a different key can't be installed over the top
  (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), so users would have to uninstall.
- To check by hand: `$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'`, then
  `& "$env:LOCALAPPDATA\Android\sdk\build-tools\37.0.0\apksigner.bat" verify --print-certs <apk>`
  should show the name and fingerprint above, never `CN=Android Debug`. (apksigner needs Java;
  none is on PATH, so use Android Studio's. The scripts pick the newest build-tools folder.)
- The Windows exe and installer aren't code-signed (the user chose not to pay for it). Every
  release has the SHA-256 checksum file instead; check a download with `Get-FileHash <file>`.

## Git
- **Look before you switch.** Run `git status -sb` before any checkout / switch / merge / pull /
  reset / stash. Unsaved changes you didn't make mean another session (or VS Code) is working:
  stop and ask. Switch with `powershell -ExecutionPolicy Bypass -File tool\switch_branch.ps1
  <branch> [-New] [-From <base>]`, which refuses in that case (exit 2) or while a flutter run is
  going (exit 3); `-Force` only for changes you made yourself.
- Remote `origin` = `https://github.com/Jamesking96/HomeTunes.git`.
- Commit messages end with the attribution lines the harness asks for (Co-Authored-By etc.).
- Merges use `--no-ff`. Earlier, `backup/*` branches were made before big merges and later deleted.
- From the cloud proxy, **deleting remote branches and pushing tags failed with a 403**. Do those
  from the PC's git instead: `git push origin --delete <branch>`, `git branch -d <branch>`.
- The user asked for only `main` to remain after merges.

## Sending files from a cloud session to the PC
`device_commit_files` writes a new file reliably, but a second write to the same path in one
session was silently not applied (28 Sep). Check with `Get-FileHash` after writing; if it didn't
land, write to `<name>.new` and `Move-Item` it over the original.

## Debugging notes
- VS Code F5 (debug) on Windows can close the app a few seconds after the scan finishes. There's
  no crash record in Windows' event log. Release builds (the zip) run fine. The user accepted
  this as debug-only; not investigated further.
- `Failed to update ui::AXTree` lines in the debug console are Flutter-on-Windows accessibility
  noise and harmless.
- Tests that use `Storage` need a short `tearDown` delay (`Future.delayed(100ms)`) before
  deleting the temp dir, because saves run in the background.
- Watch out for `Future.whenComplete(() => map.remove(key))`. When `remove` returns the future
  itself, it waits on itself and deadlocks. Use a block body. (This bit `LyricsModel`.)
