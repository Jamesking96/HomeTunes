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
   `build\dist\HomeTunes-<ver>-windows.zip` and `HomeTunes-Setup-<ver>.exe` (Inno Setup 6).
4. APK. Gradle needs this or it fails with "Unable to establish loopback connection":
   ```powershell
   $env:JAVA_TOOL_OPTIONS="-Djdk.net.unixdomain.tmpdir=C:\Temp\ht"; $env:GRADLE_OPTS=$env:JAVA_TOOL_OPTIONS
   flutter build apk --release
   Copy-Item build\app\outputs\flutter-apk\app-release.apk build\dist\HomeTunes-<ver>-android.apk
   adb install -r build\dist\HomeTunes-<ver>-android.apk
   adb shell dumpsys package com.hometunes.hometunes | Select-String versionName,versionCode
   ```
   `INSTALL_FAILED_VERSION_DOWNGRADE` means you forgot to raise the `+build` number.
5. Real-engine checks, when playback logic changes:
   ```
   flutter test tool/bench/engine_test.dart --dart-define=LIBMPV=C:\Users\James.Miller\source\hometunes\build\windows\x64\runner\Release\libmpv-2.dll
   flutter test tool/bench/player_gapless_test.dart --dart-define=LIBMPV=...same...
   ```
6. **Publishing builds for download (GitHub Releases, started 28 Sep with 0.1.20):** once main is
   merged and pushed and the three files are in `build\dist`, run
   `powershell -ExecutionPolicy Bypass -File tool\publish_release.ps1 -NotesFile <notes.md>` on the
   PC. It tags `v<version>`, creates the release and uploads the APK, the installer and the zip.
   It signs in with git's saved GitHub login (there's no `gh` on the PC). Builds are never
   committed to git. Downloads: https://github.com/Jamesking96/HomeTunes/releases
7. Probes (run with `dart run`):
   - `tool/probe_books.dart <folder>`: tags and chapters per file
   - `tool/probe_book_extras.dart <folder>`: books plus what came from sidecars
   - `tool/probe_library.dart <folder>`: grouping
   - `tool/probe_lyrics.dart "Title" "Artist" [secs]`: real LRCLIB lookup; prints counts only
   - `tool/bench_scan.dart`: scan speed

## Git
- Remote `origin` = `https://github.com/Jamesking96/HomeTunes.git`.
- Commit messages end with the attribution lines the harness asks for (Co-Authored-By etc.).
- Merges use `--no-ff`. Earlier, `backup/*` branches were made before big merges and later deleted.
- From the cloud proxy, **deleting remote branches and pushing tags failed with a 403**. Do those
  from the PC's git instead: `git push origin --delete <branch>`, `git branch -d <branch>`.
- The user asked for only `main` to remain after merges.

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
