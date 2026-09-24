# Local changes to audio_service_win

Vendored from https://github.com/HemantKArya/audio_service_win (v0.0.3, MIT licence, see LICENSE).

HomeTunes changes (windows/audio_service_win_plugin.cpp):

1. `mediaPlayer.CommandManager().IsEnabled(false)` — the MediaPlayer is only used to obtain the
   System Media Transport Controls. With its CommandManager enabled, Windows drives the SMTC from
   that empty player's state, which can keep the media overlay hidden and swallow button presses.
2. `SetupSMTC()` is called from `initializeSMTC`, so media keys are hooked up at start-up instead
   of only after the first song's details are sent.
