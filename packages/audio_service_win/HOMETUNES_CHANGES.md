# Local changes to audio_service_win

Vendored from https://github.com/HemantKArya/audio_service_win (v0.0.3, MIT licence, see LICENSE).

HomeTunes changes (windows/audio_service_win_plugin.cpp):

1. `mediaPlayer.CommandManager().IsEnabled(false)` — the MediaPlayer is only used to obtain the
   System Media Transport Controls. With its CommandManager enabled, Windows drives the SMTC from
   that empty player's state, which can keep the media overlay hidden and swallow button presses.
2. `SetupSMTC()` is called from `initializeSMTC`, so media keys are hooked up at start-up instead
   of only after the first song's details are sent.

Added in HomeTunes 0.1.17 (code review release D, fix 9):

3. Media-key presses are no longer sent to Dart from the background thread Windows calls
   `ButtonPressed` on. They're queued and run on Flutter's platform thread, woken by a registered
   window message handled through `RegisterTopLevelWindowProcDelegate` (`QueueForPlatformThread`).
   Flutter logged "sent a message from native to Flutter on a non-platform thread … may result in
   data loss or crashes" for the old code.
4. Covers: the picture is still loaded on a background thread, but it's applied to the display
   updater on the platform thread, and only if no newer song has arrived since (`coverGeneration`),
   so a quick skip no longer shows the previous song's cover and the updater is only used from one
   thread.
5. Cover paths: `+` is no longer decoded as a space (covers in folders like "Rock + Roll" work),
   and `file://server/share/...` becomes `\\server\share\...` (network-share covers work).

Added in HomeTunes 0.1.21 (security review #2):

6. The "Failed to set thumbnail in Notification" message no longer prints the cover address.
   A music-server cover address carries the login token. (HomeTunes now passes server covers as
   downloaded files anyway, see `lib/services/server_art_cache.dart`.)
