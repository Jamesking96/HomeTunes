// Windows (C++) half of the audio_service_win plugin (vendored, see HOMETUNES_CHANGES.md).
//
// Talks to the Windows "System Media Transport Controls" (SMTC): the media overlay that pops up
// with the volume keys, the lock screen's now-playing panel and the keyboard's media keys.
// The Dart side (lib/audio_service_win.dart) sends three messages over the "audio_service_win"
// channel: initializeSMTC, setMediaItem (song details + cover) and updateState (play / pause /
// stop). Button presses go the other way as "onSMTCButtonPressed".
//
// A desktop app can't get the SMTC directly, so the trick used here is to create a hidden
// Windows MediaPlayer purely to borrow its SMTC. Nothing is ever played through it; the real
// audio comes from media_kit (libmpv).
#include "audio_service_win_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Media.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <iostream>
#include <thread>
#include <fstream>  // std::ifstream
#include <vector>   // std::vector
#include <iterator> // std::istreambuf_iterator
#include <iomanip>

// Shared state for the whole plugin (there is only ever one media overlay per app):
// the borrowed MediaPlayer, its SMTC, the SMTC's "display updater" (title, artist, cover),
// the channel back to Dart, and the app id given by Dart.
static winrt::Windows::Media::Playback::MediaPlayer mediaPlayer{nullptr};
static winrt::Windows::Media::SystemMediaTransportControls smtc{nullptr};
static winrt::Windows::Media::SystemMediaTransportControlsDisplayUpdater updater{nullptr};
static std::unique_ptr<flutter::MethodChannel<>> channel;
static std::string appId;

// ---- HomeTunes (0.1.17): running work on Flutter's platform (main) thread ----
// Windows reports media-key presses, and the cover finishes loading, on background threads.
// Flutter only allows channel messages from its platform thread (anything else "may result in
// data loss or crashes", as its log warns), and the SMTC display updater is shared state, so
// that work is queued here and run by a window message handled on the platform thread.
static std::mutex taskMutex;
static std::deque<std::function<void()>> pendingTasks;
static HWND flutterView = nullptr;  // the Flutter view; its top-level window gets the message
static UINT wakeMessage = 0;        // a message id registered with Windows just for this
static flutter::PluginRegistrarWindows *pluginRegistrar = nullptr;
static int windowProcDelegateId = -1;

// Queues [task] to run on the platform thread and wakes it up. Safe from any thread.
static void QueueForPlatformThread(std::function<void()> task)
{
  {
    std::lock_guard<std::mutex> lock(taskMutex);
    pendingTasks.push_back(std::move(task));
  }
  // Looked up each time: at start-up the view isn't inside the app window yet.
  HWND top = flutterView ? GetAncestor(flutterView, GA_ROOT) : nullptr;
  if (top != nullptr && wakeMessage != 0)
  {
    PostMessage(top, wakeMessage, 0, 0);
  }
}

// Runs everything queued (called on the platform thread when the wake message arrives).
static void RunQueuedTasks()
{
  std::deque<std::function<void()>> tasks;
  {
    std::lock_guard<std::mutex> lock(taskMutex);
    tasks.swap(pendingTasks);
  }
  for (auto &task : tasks)
  {
    try
    {
      task();
    }
    catch (...)
    {
      std::cerr << "audio_service_win: a queued task failed" << std::endl;
    }
  }
}

// Goes up with every new song, so a cover that finishes loading after the song changed is
// ignored instead of replacing the new song's cover (HomeTunes 0.1.17).
static std::atomic<uint64_t> coverGeneration{0};

namespace audio_service_win
{

  // static
  void AudioServiceWinPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {

    // Guard so a second Flutter window (if one were ever opened) doesn't register it again.
    static bool plugin_already_registered = false;

    if (plugin_already_registered) {
      // Skip registration in subwindow
      return;
    }

    plugin_already_registered = true;

    // The channel name must match the MethodChannel name in lib/audio_service_win.dart.
    channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        registrar->messenger(), "audio_service_win",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<AudioServiceWinPlugin>();

    // Route every message from Dart to HandleMethodCall below.
    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    // HomeTunes: background threads wake the platform thread with this message (see
    // QueueForPlatformThread). Top-level window messages are delivered on the platform thread.
    pluginRegistrar = registrar;
    if (registrar->GetView() != nullptr)
    {
      flutterView = registrar->GetView()->GetNativeWindow();
    }
    wakeMessage = RegisterWindowMessage(L"HomeTunes.AudioServiceWin.RunTasks");
    windowProcDelegateId = registrar->RegisterTopLevelWindowProcDelegate(
        [](HWND, UINT message, WPARAM, LPARAM) -> std::optional<LRESULT>
        {
          if (wakeMessage != 0 && message == wakeMessage)
          {
            RunQueuedTasks();
            return 0;
          }
          return std::nullopt;
        });

    registrar->AddPlugin(std::move(plugin));
  }

  AudioServiceWinPlugin::AudioServiceWinPlugin() {}

  AudioServiceWinPlugin::~AudioServiceWinPlugin()
  {
    if (pluginRegistrar != nullptr && windowProcDelegateId >= 0)
    {
      pluginRegistrar->UnregisterTopLevelWindowProcDelegate(windowProcDelegateId);
      windowProcDelegateId = -1;
    }
    {
      std::lock_guard<std::mutex> lock(taskMutex);
      pendingTasks.clear();
    }
    flutterView = nullptr;
    pluginRegistrar = nullptr;
  }

  // Function to setup System Media Transport Controls (SMTC)
  // Creates the hidden MediaPlayer and hooks up the SMTC. Safe to call more than once: it does
  // nothing if it has already run.
  static void SetupSMTC()
  {
    if (mediaPlayer == nullptr)
    {
      mediaPlayer = winrt::Windows::Media::Playback::MediaPlayer();
      // HomeTunes patch: this MediaPlayer is only used to get hold of the SMTC.
      // Its CommandManager would otherwise drive the SMTC from the player's own
      // (empty, "closed") state and hide the Windows media overlay.
      mediaPlayer.CommandManager().IsEnabled(false);
      smtc = mediaPlayer.SystemMediaTransportControls();
      updater = smtc.DisplayUpdater();
      updater.AppMediaId(winrt::to_hstring(appId));

      // Buttons shown on the overlay. The whole control stays hidden until there's a song to show.
      smtc.IsPlayEnabled(true);
      smtc.IsPauseEnabled(true);
      smtc.IsNextEnabled(true);
      smtc.IsPreviousEnabled(true);
      smtc.IsEnabled(false); // Keep disabled until setMediaItem

      std::cout << "SMTC initialized with appid: " << appId << std::endl;

      // When a media key or overlay button is pressed, turn it into a short name
      // ("play", "next"...) and send it to Dart. Dart only acts on play, pause, stop, next,
      // previous, fastForward and rewind.
      // Windows calls this on a background thread, so the message to Dart is queued for the
      // platform thread (HomeTunes 0.1.17; it used to be sent straight from here).
      smtc.ButtonPressed([](auto const &, winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs const &args)
                         {
                           auto method = std::make_shared<std::string>();
                           switch (args.Button())
                           {
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Play:
                             *method = "play";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Pause:
                             *method = "pause";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Next:
                             *method = "next";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Previous:
                             *method = "previous";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Stop:
                             *method = "stop";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::FastForward:
                             *method = "fastForward";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Rewind:
                             *method = "rewind";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::Record:
                             *method = "record";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::ChannelUp:
                             *method = "channelUp";
                             break;
                           case winrt::Windows::Media::SystemMediaTransportControlsButton::ChannelDown:
                             *method = "channelDown";
                             break;
                           default:
                             *method = "other";
                             break;
                           }
                           QueueForPlatformThread([method]()
                                               {
                                                 if (channel)
                                                 {
                                                   channel->InvokeMethod(
                                                       "onSMTCButtonPressed",
                                                       std::make_unique<flutter::EncodableValue>(*method));
                                                 }
                                               });
                         });
    }
  }

} // namespace audio_service_win

namespace audio_service_win
{

  // Turns "%20"-style codes back into the characters they stand for. HomeTunes (0.1.17): "+" is
  // left alone; it used to become a space, so covers in folders like "Rock + Roll" didn't load.
  // (Dart's Uri.file never writes a space as "+".) The result is UTF-8, as to_hstring expects.
  std::string PercentDecode(const std::string &encoded)
  {
    std::string result;
    result.reserve(encoded.size());
    for (size_t i = 0; i < encoded.size(); ++i)
    {
      if (encoded[i] == '%' && i + 2 < encoded.size() && isxdigit(static_cast<unsigned char>(encoded[i + 1])) &&
          isxdigit(static_cast<unsigned char>(encoded[i + 2])))
      {
        result.push_back(static_cast<char>(std::stoi(encoded.substr(i + 1, 2), nullptr, 16)));
        i += 2;
      }
      else
      {
        result.push_back(encoded[i]);
      }
    }
    return result;
  }

  // "file:///C:/Music/x.jpg" -> "C:\Music\x.jpg", and (HomeTunes 0.1.17) network shares:
  // "file://server/share/x.jpg" -> "\\server\share\x.jpg" (they used to lose part of the name).
  // Anything that isn't a file:// address is treated as a plain path.
  std::string FileUriToPath(const std::string &uri)
  {
    std::string path = uri;
    if (path.rfind("file:///", 0) == 0)
    {
      path = path.substr(8); // drive letter paths
    }
    else if (path.rfind("file://", 0) == 0)
    {
      path = "//" + path.substr(7); // network share: file://server/share/...
    }
    path = PercentDecode(path);
    std::replace(path.begin(), path.end(), '/', '\\');
    return path;
  }

  // Handles each message from Dart: initializeSMTC, setMediaItem, updateState.
  void AudioServiceWinPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {

    // Initialize System Media Transport Controls (SMTC) but do NOT enable or update notification yet
    if (method_call.method_name().compare("initializeSMTC") == 0)
    {
      std::cout << "Starting SMTC..." << std::endl;

      // Extract the appid argument from the method call
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("appid")) != arguments->end())
      {
        appId = std::get<std::string>(arguments->at(flutter::EncodableValue("appid")));

        // HomeTunes patch: set up SMTC now so media keys work from the start.
        SetupSMTC();

        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "appid is required");
      }
    }

    // Set/Update new Media metadata
    else if (method_call.method_name().compare("setMediaItem") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("title")) != arguments->end() &&
          arguments->find(flutter::EncodableValue("artist")) != arguments->end() &&
          arguments->find(flutter::EncodableValue("album")) != arguments->end())
      {
        // Read title / artist / album; a missing or null value becomes an empty string.
        std::string title;
        const auto &titleValue =
            arguments->at(flutter::EncodableValue("title"));
        if (!titleValue.IsNull() &&
            std::holds_alternative<std::string>(titleValue)) {
          title = std::get<std::string>(titleValue);
        }

        std::string artist;
        const auto &artistValue =
            arguments->at(flutter::EncodableValue("artist"));
        if (!artistValue.IsNull() &&
            std::holds_alternative<std::string>(artistValue)) {
          artist = std::get<std::string>(artistValue);
        }

        std::string album;
        const auto &albumValue =
            arguments->at(flutter::EncodableValue("album"));
        if (!albumValue.IsNull() &&
            std::holds_alternative<std::string>(albumValue)) {
          album = std::get<std::string>(albumValue);
        }

        // Ensure SMTC is initialized
        if (!smtc)
        {
          SetupSMTC();
        }

        // The cover is optional.
        std::string artUri;
        if (arguments->find(flutter::EncodableValue("artUri")) != arguments->end())
        {
          const auto &artUriValue = arguments->at(flutter::EncodableValue("artUri"));
          if (!artUriValue.IsNull() && std::holds_alternative<std::string>(artUriValue))
          {
            artUri = std::get<std::string>(artUriValue);
          }
        }

        if (updater)
        {
          // Show the overlay and replace everything it showed before with the new song's details.
          smtc.IsEnabled(true);
          updater.ClearAll();
          updater.Type(winrt::Windows::Media::MediaPlaybackType::Music);
          updater.MusicProperties().Title(winrt::to_hstring(title));
          updater.MusicProperties().Artist(winrt::to_hstring(artist));
          updater.MusicProperties().AlbumTitle(winrt::to_hstring(album));

          // Every new song gets a new number; a cover that loads late for an older song is
          // then ignored (HomeTunes 0.1.17: a quick skip used to show the previous cover).
          const uint64_t generation = ++coverGeneration;
          if (!artUri.empty())
          {
            try
            {
              // Loading the cover can be slow (a download or a file read), so it's done on a
              // separate thread. The text details are shown straight away (Update() below).
              // HomeTunes (0.1.17): the loaded picture is handed back to the platform thread,
              // which applies it only if the song hasn't changed, so the display updater is only
              // ever touched from one thread.
              std::thread([artUri, generation]()
                          {
                // Each new thread must set up Windows' COM system before using WinRT objects.
                winrt::init_apartment(winrt::apartment_type::multi_threaded);
                try {
                  winrt::Windows::Storage::Streams::RandomAccessStreamReference thumbRef{nullptr};
                  // Server covers: let Windows fetch the picture from the web address itself.
                  if (artUri.rfind("http://", 0) == 0 || artUri.rfind("https://", 0) == 0) {
                    winrt::Windows::Foundation::Uri uri(winrt::to_hstring(artUri));
                    thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(uri);
                  } else {
                    auto storageFile = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(
                        winrt::to_hstring(FileUriToPath(artUri))).get();
                    thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromFile(storageFile);
                  }
                  if (generation == coverGeneration.load()) {
                    QueueForPlatformThread([thumbRef, generation]() {
                      if (generation != coverGeneration.load() || !updater) return; // a newer song
                      updater.Thumbnail(thumbRef);
                      updater.Update();
                    });
                  }
                } catch (const winrt::hresult_error& e) {
                  std::cerr << "Failed to set thumbnail: " << winrt::to_string(e.message()) << std::endl;
                } catch (...) {
                  std::cerr << "Failed to set thumbnail" << std::endl;
                }
                winrt::uninit_apartment(); })
                  .detach();
            }
            catch (...)
            {
              // If thumbnail fails, continue without it. HomeTunes (0.1.21): the address isn't
              // logged; a server cover address carries the login token.
              std::cerr << "Failed to set thumbnail in Notification" << std::endl;
            }
          }
          updater.Update();
        }
        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "title, artist, and album are required");
      }
    }

    // Update State
    else if (method_call.method_name().compare("updateState") == 0)
    {
      const auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments && arguments->find(flutter::EncodableValue("state")) != arguments->end())
      {
        // 0 = playing, 1 = paused, 2 = stopped (see setState / stopService on the Dart side).
        int32_t state = std::get<int32_t>(arguments->at(flutter::EncodableValue("state")));
        if (smtc)
        {
          smtc.IsEnabled(true);
          switch (state)
          {
          case 0: // Playing
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Playing);
            break;
          case 1: // Paused
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Paused);
            break;
          case 2: // Stopped
            smtc.PlaybackStatus(winrt::Windows::Media::MediaPlaybackStatus::Stopped);
            ++coverGeneration; // a cover still loading must not reappear
            // Stopped: hide the overlay and wipe its details.
            smtc.IsEnabled(false);
            updater.ClearAll();
            updater.Update();
            break;
          default:
            result->Error("InvalidArguments", "Invalid playback state");
            return;
          }
        }
        result->Success();
      }
      else
      {
        result->Error("InvalidArguments", "state is required");
      }
    }

    else
    {
      // Any other message name isn't supported.
      result->NotImplemented();
    }
  }

} // namespace audio_service_win
