// Applies the video player look (Settings › Appearance › Video player, 0.1.40) to the
// media_kit controls, and draws the preview shown in Settings.
//
// media_kit's controls read their colour and size from the theme data, so both the
// normal and the full-screen theme get them (full screen is its own route and doesn't
// inherit anything from the page). Each button in the bar is wrapped in a
// [ButtonBacking]: a soft halo or a disc in the opposite shade to the buttons, so
// they can be seen over a black scene as well as a white one.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/video_player_look.dart';
import 'wheel_seek.dart';

/// Puts the chosen backing behind one control of the video player's bar.
class ButtonBacking extends StatelessWidget {
  const ButtonBacking({super.key, required this.look, required this.accent, required this.child});

  final VideoPlayerLook look;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final back = look.backingColour(accent);
    switch (look.backing) {
      case VideoButtonBacking.none:
        return child;
      case VideoButtonBacking.glow:
        // A blurred halo behind the button, plus a crisp shadow on the icon itself.
        return IconTheme.merge(
          data: IconThemeData(shadows: [Shadow(color: back, blurRadius: 6)]),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [BoxShadow(color: back, blurRadius: 16, spreadRadius: -6)],
            ),
            child: child,
          ),
        );
      case VideoButtonBacking.circle:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: DecoratedBox(
            decoration: ShapeDecoration(shape: const StadiumBorder(), color: back),
            child: child,
          ),
        );
    }
  }
}

/// Wraps every control of a bar in its backing ([Spacer]s stay as they are: a Row needs them bare).
List<Widget> backedBar(List<Widget> bar, VideoPlayerLook look, Color accent) => [
  for (final w in bar)
    if (w is Spacer || w is Expanded || w is SizedBox) w else ButtonBacking(look: look, accent: accent, child: w),
];

/// The time text ("1:02 / 45:10"), with room around it for a backing.
TextStyle timeTextStyle(VideoPlayerLook look, Color accent, {bool phone = false}) {
  final base = switch (look.size) {
    VideoButtonSize.small => 11.0,
    VideoButtonSize.normal => 12.0,
    VideoButtonSize.large => 15.0,
  };
  return TextStyle(
    height: 1.0,
    fontSize: phone ? base + 1 : base,
    color: look.buttons(accent),
    shadows: look.backing == VideoButtonBacking.glow
        ? [Shadow(color: look.backingColour(accent), blurRadius: 4)]
        : null,
  );
}

/// The time text with a little space around it, so a disc behind it reads as a pill.
Widget paddedTime(Widget indicator) =>
    Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: indicator);

/// Height of the button bar along the bottom of the video (taller for large buttons).
double videoButtonBarHeight(VideoPlayerLook look) => look.size.desktop + 32 > 56 ? look.size.desktop + 32 : 56;

/// Where media_kit's desktop progress bar sits, measured up from the bottom of the video: it's
/// 36 px tall and drawn 16 px down into the button bar (material_desktop.dart, 2.0.1).
({double bottom, double top}) videoSeekBarBand(VideoPlayerLook look, {double bottomPadding = 0}) {
  final bottom = videoButtonBarHeight(look) - 16 + bottomPadding;
  return (bottom: bottom, top: bottom + 36);
}

/// media_kit's desktop controls, in the chosen look.
MaterialDesktopVideoControlsThemeData desktopControlsTheme(
  VideoPlayerLook look,
  Color accent, {
  required List<Widget> bar,
  Map<ShortcutActivator, VoidCallback>? keys,
  List<Widget> top = const [],
}) {
  final buttons = look.buttons(accent), seek = look.seek(accent), track = look.seekTrack(accent);
  return MaterialDesktopVideoControlsThemeData(
    bottomButtonBar: backedBar(bar, look, accent),
    // 0.1.59: buttons along the top (full screen: a round "Leave full screen" button).
    topButtonBar: top,
    keyboardShortcuts: keys,
    buttonBarHeight: videoButtonBarHeight(look),
    // The page's own wheel handling does volume, and skipping over the progress bar (30 Sep).
    modifyVolumeOnScroll: false,
    buttonBarButtonSize: look.size.desktop,
    buttonBarButtonColor: buttons,
    seekBarColor: track,
    seekBarHoverColor: track,
    seekBarBufferColor: track,
    seekBarPositionColor: seek,
    seekBarThumbColor: seek,
    volumeBarColor: track,
    volumeBarActiveColor: buttons,
    volumeBarThumbColor: buttons,
  );
}

/// media_kit's phone controls, in the chosen look. The backdrop dims the whole picture
/// while the controls show; it follows the backing (the default 40% when there's none).
MaterialVideoControlsThemeData phoneControlsTheme(
  VideoPlayerLook look,
  Color accent, {
  required List<Widget> bar,
  required Duration skipBack,
  required Duration skipForward,
  List<Widget> top = const [],
}) {
  final buttons = look.buttons(accent), seek = look.seek(accent), track = look.seekTrack(accent);
  final shade = isLightColour(buttons) ? Colors.black : Colors.white;
  return MaterialVideoControlsThemeData(
    bottomButtonBar: backedBar(bar, look, accent),
    // 0.1.59: buttons along the top (full screen: a round "Leave full screen" button).
    topButtonBar: top,
    seekOnDoubleTap: true,
    seekOnDoubleTapBackwardDuration: skipBack,
    seekOnDoubleTapForwardDuration: skipForward,
    backdropColor: shade.withValues(alpha: look.backing == VideoButtonBacking.none ? 0.4 : look.backingStrength * 0.75),
    buttonBarButtonSize: look.size.phone,
    buttonBarButtonColor: buttons,
    seekBarColor: track,
    seekBarBufferColor: track,
    seekBarPositionColor: seek,
    seekBarThumbColor: seek,
  );
}

/// The mouse wheel over the video (30 Sep): over its progress bar a notch skips 5 s (up =
/// forward); anywhere else it turns the volume up or down by 5, as media_kit's own did. Wraps the
/// controls (so it's in full screen too); scroll events only, clicks and hovering pass through.
class VideoWheel extends StatefulWidget {
  const VideoWheel({super.key, required this.player, required this.look, required this.child});

  final Player player;
  final VideoPlayerLook look;
  final Widget child;

  @override
  State<VideoWheel> createState() => _VideoWheelState();
}

class _VideoWheelState extends State<VideoWheel> {
  Duration? _lastTarget;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Whether [y] (from the top of a box [height] tall) is on the progress bar.
  bool _onSeekBar(double y, double height, double bottomPadding) {
    final band = videoSeekBarBand(widget.look, bottomPadding: bottomPadding);
    final fromBottom = height - y;
    return fromBottom >= band.bottom && fromBottom <= band.top;
  }

  void _scroll(double dy, bool onBar) {
    final p = widget.player;
    if (dy == 0) return;
    if (!onBar) {
      p.setVolume((p.state.volume + (dy > 0 ? -5.0 : 5.0)).clamp(0.0, 100.0));
      return;
    }
    final now = DateTime.now();
    final from = _lastTarget != null && now.difference(_lastAt) < const Duration(milliseconds: 700)
        ? _lastTarget!
        : p.state.position;
    final to = wheelSeekTarget(from, p.state.duration, dy);
    if (to == null) return;
    _lastTarget = to;
    _lastAt = now;
    p.seek(to);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.maybeOf(context)?.padding.bottom ?? 0;
    return LayoutBuilder(
      builder: (context, box) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          final onBar = _onSeekBar(event.localPosition.dy, box.maxHeight, bottomPadding);
          GestureBinding.instance.pointerSignalResolver
              .register(event, (e) => _scroll((e as PointerScrollEvent).scrollDelta.dy, onBar));
        },
        child: widget.child,
      ),
    );
  }
}

/// Which made-up picture the preview shows the buttons over.
enum PreviewScene {
  dark('Dark scene', [Color(0xFF000000), Color(0xFF0A0A0E)]),
  bright('Bright scene', [Color(0xFFFFFFFF), Color(0xFFE8EEF3)]),
  busy('Busy scene', [Color(0xFF1E5A8A), Color(0xFFF2C14E), Color(0xFFE4572E), Color(0xFF2E2E2E)]);

  const PreviewScene(this.label, this.colours);
  final String label;
  final List<Color> colours;
}

/// A still of the player's bottom bar in the chosen look, over a dark, bright or busy
/// picture, so the choice can be judged before playing anything.
class VideoControlsPreview extends StatelessWidget {
  const VideoControlsPreview({super.key, required this.look, required this.accent, this.scene = PreviewScene.dark});

  final VideoPlayerLook look;
  final Color accent;
  final PreviewScene scene;

  @override
  Widget build(BuildContext context) {
    final buttons = look.buttons(accent);
    Widget icon(IconData i) =>
        IconButton(onPressed: () {}, icon: Icon(i), iconSize: look.size.desktop, color: buttons, splashRadius: 1);
    final bar = backedBar(
      [
        icon(Icons.replay_10),
        icon(Icons.pause),
        icon(Icons.forward_10),
        icon(Icons.volume_up),
        paddedTime(Text('12:34 / 45:10', style: timeTextStyle(look, accent))),
        const SizedBox(width: 40),
        icon(Icons.speed),
        icon(Icons.subtitles_outlined),
        icon(Icons.fullscreen),
      ],
      look,
      accent,
    );
    return AspectRatio(
      aspectRatio: 16 / 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: scene.colours,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: scene == PreviewScene.busy ? const [0.0, 0.45, 0.7, 1.0] : null,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // The seek bar: the played part, then the rest in the faded button colour.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Container(height: 3.2, color: look.seek(accent))),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: look.seek(accent), shape: BoxShape.circle),
                    ),
                    Expanded(flex: 7, child: Container(height: 3.2, color: look.seekTrack(accent))),
                  ],
                ),
              ),
              SizedBox(
                height: look.size.desktop + 32 > 56 ? look.size.desktop + 32 : 56,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    // Its natural width, shrunk to fit (the real bar has room between the groups).
                    child: Row(mainAxisSize: MainAxisSize.min, children: bar),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
