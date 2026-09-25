// Declares the Windows (C++) half of the audio_service_win plugin. The code itself is in
// audio_service_win_plugin.cpp; this header only exists so Flutter's generated plugin
// registration (via audio_service_win_plugin_c_api.cpp) can create and register the plugin.
#ifndef FLUTTER_PLUGIN_AUDIO_SERVICE_WIN_PLUGIN_H_
#define FLUTTER_PLUGIN_AUDIO_SERVICE_WIN_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace audio_service_win {

// One instance per app. It receives messages from the Dart side on the "audio_service_win"
// channel and drives the Windows System Media Transport Controls (SMTC).
class AudioServiceWinPlugin : public flutter::Plugin {
 public:
  // Creates the plugin and its message channel; called once when the app starts.
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  AudioServiceWinPlugin();

  virtual ~AudioServiceWinPlugin();

  // Disallow copy and assign.
  AudioServiceWinPlugin(const AudioServiceWinPlugin&) = delete;
  AudioServiceWinPlugin& operator=(const AudioServiceWinPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace audio_service_win

#endif  // FLUTTER_PLUGIN_AUDIO_SERVICE_WIN_PLUGIN_H_
