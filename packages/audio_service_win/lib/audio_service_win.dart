// Windows side of the audio_service package (vendored copy, see HOMETUNES_CHANGES.md).
//
// audio_service is the package HomeTunes uses to show "now playing" in the system: on Android
// the notification and lock screen, on Windows the media overlay (SMTC = System Media Transport
// Controls) and the keyboard media keys. audio_service only knows how to do Android/iOS itself;
// on Windows it hands every call to this class. This class forwards the details over a
// MethodChannel to the C++ code in windows/audio_service_win_plugin.cpp, and passes media-key
// presses coming back from C++ to HomeTunes' audio handler (lib/services/media_session.dart).
import 'dart:developer';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/services.dart';

/// Plugs into audio_service as its Windows "platform" implementation.
class AudioServiceWin extends AudioServicePlatform {
  /// The app's handler for button presses (play, pause, next...), given to us by audio_service.
  AudioHandlerCallbacks? _handlerCallbacks;
  /// The link to the C++ plugin; the name must match the one used in the .cpp file.
  final methodChannel = const MethodChannel('audio_service_win');
  bool _methodCallHandlerSet = false;

  /// Called automatically by Flutter at start-up (Windows only) to make this class the one
  /// audio_service talks to.
  static void registerWith() {
    final instance = AudioServiceWin();
    AudioServicePlatform.instance = instance;
  }

  @override
  /// Called once when the app starts audio_service. Starts listening for button presses and
  /// asks the C++ side to set up the Windows media controls straight away.
  Future<void> configure(ConfigureRequest request) async {
    log('Configure AudioServiceWin.', name: 'audio_service_win');
    // The Android channel id is reused as the Windows "app media id" (the original author's
    // choice), so it must be set even on Windows.
    assert(request.config.androidNotificationChannelId != null,
        "androidNotificationChannelId is required for registering DBus object. e.g com.ryanheise.myapp.channel.audio");

    // Set up method call handler if not already done
    if (!_methodCallHandlerSet) {
      await _setupMethodCallHandler();
      _methodCallHandlerSet = true;
    }

    await methodChannel.invokeMethod<String>('initializeSMTC',
        {'appid': request.config.androidNotificationChannelId});
  }

  @override
  /// Sends the current song's title, artist, album and cover to the Windows media overlay.
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    log('Set Media Item in AudioServiceWin.', name: 'audio_service_win');

    await methodChannel.invokeMethod('setMediaItem', {
      'title': request.mediaItem.title,
      'artist': request.mediaItem.artist,
      'album': request.mediaItem.album,
      // A file:// path for a local cover or an http(s) address for a server cover.
      // Note: with no cover, artUri is null and this sends the text "null".
      'artUri': request.mediaItem.artUri.toString(),
    });
  }

  @override
  /// Tells Windows whether we're playing or paused, so the overlay shows the right button.
  Future<void> setState(SetStateRequest request) async {
    /* States:
    0: Playing
    1: Paused
    2: Stopped
    */
    int state = 0;
    switch (request.state.playing) {
      case true:
        state = 0; // Playing
        break;
      case false:
        state = 1; // Paused
        break;
    }
    await methodChannel.invokeMethod('updateState', {'state': state});
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {
    // Windows media controls have no "up next" list, so there's nothing to
    // do here (and nothing to warn about).
  }

  @override
  /// Playback stopped completely: state 2 hides the overlay and clears its details.
  Future<void> stopService(StopServiceRequest request) async {
    await methodChannel.invokeMethod('updateState', {'state': 2});
  }

  /// Listens for messages from the C++ side. The only one is "a media button was pressed",
  /// which is turned into the matching audio_service request for the app's handler.
  Future<void> _setupMethodCallHandler() async {
    methodChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSMTCButtonPressed') {
        final button = call.arguments;
        log('SMTC Button Pressed: $button', name: 'audio_service_win');

        // Handle button presses using callbacks if available
        // Presses before the app's handler is ready are simply ignored.
        if (_handlerCallbacks != null) {
          switch (button) {
            case 'play':
              _handlerCallbacks!.play(const PlayRequest());
              break;
            case 'pause':
              _handlerCallbacks!.pause(const PauseRequest());
              break;
            case 'stop':
              _handlerCallbacks!.stop(const StopRequest());
              break;
            case 'next':
              _handlerCallbacks!.skipToNext(const SkipToNextRequest());
              break;
            case 'previous':
              _handlerCallbacks!.skipToPrevious(const SkipToPreviousRequest());
              break;
            case 'fastForward':
              _handlerCallbacks!.fastForward(const FastForwardRequest());
              break;
            case 'rewind':
              _handlerCallbacks!.rewind(const RewindRequest());
              break;
            default:
              log('Unhandled button: $button', name: 'audio_service_win');
              break;
          }
        }
      }
    });
  }

  @override
  /// audio_service calls this to give us the app's handler (see [_handlerCallbacks]).
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    _handlerCallbacks = callbacks;
  }
}
