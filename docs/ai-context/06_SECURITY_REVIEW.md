# Security review — 2026-09-28 (v0.1.20)

Static review of lib/, the two vendored packages, Android/macOS/Windows config, and the release scripts. Checked git history and tracked files for secrets (none found); `flutter pub outdated` shows all direct dependencies current.

## Status: all ten fixed in 0.1.21 (branch `security-fixes`, 28 Sep)
The user asked for all fixes at once, so the planned 0.1.21–0.1.23 split was collapsed into 0.1.21.
`flutter analyze` is clean and `flutter test` passes (291 tests, new ones in `test/security_fixes_test.dart`).
The signed APK and the Windows zip and installer are built in `build\dist\`. What each fix does is in `05_CODE_GUIDE.md` → "Fixed in 0.1.21".
- **Installed on the Pixel 8 on 28 Sep (18:24).** 0.1.20 was uninstalled first; the user's backup is on an external hard drive. The app starts cleanly, and `ALLOW_BACKUP` is gone from its flags. The user restores the backup and types the server password.
- **Not done yet:** the branch isn't committed or merged.
- **Release key:** `CN=James Miller`, SHA-256 `758f6618fcb4b2832114d53b7ec887d03cfa4d923976ff602a2988d2c0ff1030`. The key is at `C:\Users\James.Miller\keys\hometunes-release.jks`, and `android/key.properties` is gitignored. Never read or print either.
- **Accepted as they are:**
  - `usesCleartextTraffic` stays on, because LAN servers need http. The risk is covered by #4.
  - The Windows build isn't code-signed; checksums are published instead.
  - The engine libraries (#8) were already the newest available.

## Fix plan (as agreed)
Published as an artifact: "HomeTunes Security Fix Plan" (https://claude.ai/artifact/PBV5TRiFopdA2mimDTAkLi), 28 Sep 2026, version 2.
- **Decisions (the user took the recommended option each time):**
  - D1: switch to a real release key now.
  - D2: Android cloud backup off completely.
  - D3: remove "include server password" from backups.
  - D4: ask once per server before plain http to an internet host.
  - D5: checksums now, with no paid Windows code signing.

## Medium
1. **Release APK is signed with the debug key** (`android/app/build.gradle.kts`, `signingConfig = signingConfigs.getByName("debug")`). `publish_release.ps1` posts these APKs publicly. The debug keystore uses the well-known password "android", and switching keys later forces users to uninstall. Fix: create a release keystore and load it from a gitignored `key.properties`. **Fixed in 0.1.21.**
2. **The Subsonic login token leaves the app.** `artUriFor` → `coverArtUrl` puts `t`+`s` into the Android MediaSession `artUri` (`media_session.dart:123`), where other apps with media/notification access can read it. `audio_service_win_plugin.cpp:441` also writes the URL to stderr. A token and salt pair can be replayed (most servers don't check nonces) and allows an offline MD5 brute-force of the password. Fix: download the cover to a cache file, pass a `file://` URI, and don't log `artUri`. **Fixed in 0.1.21.**
3. **Paths from a restored backup are trusted.** `fromPortable` only checks `@app/` paths, so absolute paths in `library.json`/`edits.json` pass through unchanged. `book_screen.dart:_openFile` then runs `explorer.exe <path>` on companions without checking them. A crafted `.htbackup` could point at `\\host\share\x.exe` (which also leaks the NTLM hash) or a local .exe. The edit's `art` path can also pull any file into a tag write-back. Fix: in `_openFile`, require an extension in `companionExtensions`, a local non-UNC path, and a file that exists. On restore, drop absolute paths that aren't under the configured folders. **Fixed in 0.1.21.**

## Low
4. `usesCleartextTraffic="true"` applies to the whole app. `connectServer` falls back from https to http after any network error, so someone on the network can force a downgrade. The UI warns, but consider asking for confirmation before falling back for non-LAN hosts. **Fixed in 0.1.21 (asks once per host).**
5. Android `allowBackup` is on by default and there are no dataExtractionRules, so the library, playlists and listening history go to cloud backup. The password is safe in the Keystore. **Fixed in 0.1.21 (off).**
6. The opt-in "include server password" in a backup is stored as plain text (the UI says so). Consider encrypting it with a passphrase instead. **Fixed in 0.1.21 (option removed).**
7. Reads have no size limits, so crafted files can cause memory spikes or crashes: `.lrc` files are read whole (`local_lyrics.dart:45`), backups are gunzipped with no cap (decompression bomb), and the vendored parser allocates `Uint8List(size)` using sizes taken from the file. **Fixed in 0.1.21.**
8. media_kit ships libmpv/ffmpeg 6.0 (2023), which parses untrusted media. Keep media_kit_libs_audio current. **Checked 28 Sep: already the newest available.**
9. The Windows installer and exe aren't signed, and releases have no checksums. **Checksums added in 0.1.21.**
10. On Linux the password stays in settings.json. The `FLUTTER_TEST` env var switches the secret store to memory in any build. **Fixed in 0.1.21.**

## Already good
Salts come from `Random.secure`, the password migrated to protected storage, `hideSecrets` is applied to error text, backup art writes are protected against path traversal (`safeArtDestination`), JSON writes are atomic, all third-party APIs use https, the EQ filter string is numbers only, and local playback requires an existing file.

## Not covered
MainActivity.kt (the path is too deeply nested to stage), iOS/Linux runners, most of the vendored parsers (only skimmed), no dynamic testing.
