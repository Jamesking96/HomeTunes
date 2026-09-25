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

#include <memory>
#include <sstream>
#include <iostream>
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

    registrar->AddPlugin(std::move(plugin));
  }

  AudioServiceWinPlugin::AudioServiceWinPlugin() {}

  AudioServiceWinPlugin::~AudioServiceWinPlugin() {}

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
      // (Note: Windows calls this from a background thread, not Flutter's main thread.)
      smtc.ButtonPressed([](auto const &, winrt::Windows::Media::SystemMediaTransportControlsButtonPressedEventArgs const &args)
                         {
                           std::string *method = new std::string;
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
                           channel->InvokeMethod(
                               "onSMTCButtonPressed",
                               std::make_unique<flutter::EncodableValue>(*method));
                           delete method; // Clean up the dynamically allocated string
                         });
    }
  }

} // namespace audio_service_win

namespace audio_service_win
{

  // Turns "%20"-style codes in a file:// address back into normal characters (and "+" into a
  // space), so the cover's real file path can be opened.
  std::string UrlDecode(const std::string &encoded)
  {
    std::ostringstream result;
    for (size_t i = 0; i < encoded.size(); ++i)
    {
      if (encoded[i] == '%' && i + 2 < encoded.size())
      {
        int value;
        std::istringstream is(encoded.substr(i + 1, 2));
        if (is >> std::hex >> value)
        {
          result << static_cast<char>(value);
          i += 2;
        }
        else
        {
          result << encoded[i];
        }
      }
      else if (encoded[i] == '+')
      {
        result << ' ';
      }
      else
      {
        result << encoded[i];
      }
    }
    return result.str();
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

          if (!artUri.empty())
          {
            try
            {

              // Loading the cover can be slow (a download or a file read), so it's done
              // on a separate thread. The text details are shown straight away (Update()
              // further down); this thread adds the picture and calls Update() again
              // once it has loaded.
              std::thread([artUri]()
                          {
              // Each new thread must set up Windows' COM system before using WinRT objects.
              winrt::init_apartment(winrt::apartment_type::multi_threaded);
              try {
                  // Server covers: let Windows fetch the picture from the web address itself.
                  if (artUri.rfind("http://", 0) == 0 || artUri.rfind("https://", 0) == 0) {
                      winrt::Windows::Foundation::Uri uri(winrt::to_hstring(artUri));
                      auto thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromUri(uri);
                      updater.Thumbnail(thumbRef);
                  } else {
                      // Local covers: "file:///C:/Music/x.jpg" -> "C:\Music\x.jpg"
                      // (drop the 8 characters of "file:///", use Windows backslashes),
                      // then undo the %-encoding.
                      std::string localPath = artUri;
                      if (localPath.rfind("file://", 0) == 0) {
                          localPath = localPath.substr(8);
                          std::replace(localPath.begin(), localPath.end(), '/', '\\');
                      }
                      auto storageFile = winrt::Windows::Storage::StorageFile::GetFileFromPathAsync(winrt::to_hstring(UrlDecode(localPath))).get();
                      auto thumbRef = winrt::Windows::Storage::Streams::RandomAccessStreamReference::CreateFromFile(storageFile);
                      updater.Thumbnail(thumbRef);
                  }
                  updater.Update();
              } catch (const winrt::hresult_error& e) {
                  std::cerr << "Failed to set thumbnail: " << e.message().c_str() << std::endl;
              } })
                  .detach();
            }
            catch (...)
            {
              // If thumbnail fails, continue without it
              std::cerr << "Failed to set thumbnail in Notification: " << artUri << std::endl;
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
