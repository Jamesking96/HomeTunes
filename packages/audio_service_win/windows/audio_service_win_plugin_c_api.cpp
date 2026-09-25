// The plain-C entry point Flutter's generated code (generated_plugin_registrant.cc in the
// app's windows/ folder) calls at start-up. It just finds the C++ registrar and hands it to
// AudioServiceWinPlugin::RegisterWithRegistrar. Standard Flutter plugin boilerplate.
#include "include/audio_service_win/audio_service_win_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "audio_service_win_plugin.h"

void AudioServiceWinPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  audio_service_win::AudioServiceWinPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
