// The screen HomeTunes shows while it opens. 0.2.12: the user (8 Nov 2026): "update the TV build
// so that the opening screen isn't just a white screen". 0.2.13: the user's own picture
// ("have this as the new landing image for when Hometunes loads up": HomeTunes_Splash, 16:9, in
// assets/ at 1920 x 1080 and 3840 x 2160).
//
// On Android the launch window shows the same picture (android/app/src/main/res/drawable*/
// launch_background.xml) until Flutter draws; main.dart then shows this at once, while the saved
// files are read (about 3.5 s on the test TV), and swaps in the app when they're ready.
// The PC shows it too while it loads. The picture is fitted whole into the screen (a TV: exactly;
// a phone held upright: across its width) on the colour round its edges, so there's no seam. If
// opening takes more than a second, "Loading your library…" fades in under the picture's sound
// bars, so a slow start doesn't look stuck.
//
// It runs before the settings are read, so nothing here depends on the theme.
import 'dart:async';

import 'package:flutter/widgets.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.wordsAfter = const Duration(seconds: 1)});

  /// How long before "Loading your library…" shows.
  final Duration wordsAfter;

  /// The colour round the picture's edges (and the launch window's, res/values/colors.xml).
  static const background = Color(0xFF0B0C0E);

  /// The picture's shape.
  static const aspect = 16 / 9;

  /// The two sizes of the picture: the big one only where it would be shown wider than the small
  /// one has pixels for (a 4K screen), as the small one decodes much faster.
  static const small = 'assets/splash_1920x1080.png', large = 'assets/splash_3840x2160.png';

  /// Which picture for a screen [physicalWidth] pixels across.
  static String pictureFor(double physicalWidth) => physicalWidth > 1920 ? large : small;

  /// The picture as last shown, so main.dart can let its memory go once the app is up.
  static ImageProvider? shown;

  /// Where the words go, as a share of the picture's height (just under its sound bars).
  static const wordsAt = 0.955;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  Timer? _timer;
  bool _words = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.wordsAfter, () {
      if (mounted) setState(() => _words = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: StartScreen.background,
        child: LayoutBuilder(builder: (context, box) {
          // The picture fitted whole, in the middle.
          var w = box.maxWidth, h = w / StartScreen.aspect;
          if (h > box.maxHeight) {
            h = box.maxHeight;
            w = h * StartScreen.aspect;
          }
          final ratio = media?.devicePixelRatio ?? 1;
          return Center(
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(children: [
                Positioned.fill(
                  child: Image(
                    // Decoded at the size it's shown (less memory and time on a TV).
                    image: StartScreen.shown = ResizeImage(AssetImage(StartScreen.pictureFor(w * ratio)), width: (w * ratio).round()),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: 'HomeTunes',
                    // Fades in once decoded, over the edge colour (no flash).
                    frameBuilder: (context, child, frame, sync) => sync
                        ? child
                        : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 200), child: child),
                  ),
                ),
                // Space above and below (a phone held upright): the picture's top and bottom fade
                // into the background, so its glow doesn't end in a line.
                if (box.maxHeight - h > 1)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [StartScreen.background, Color(0x000B0C0E), Color(0x000B0C0E), StartScreen.background],
                            stops: [0, 0.12, 0.88, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * StartScreen.wordsAt - h * 0.015,
                  child: AnimatedOpacity(
                    opacity: _words ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      'Loading your library…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFFA3A8B3),
                        fontSize: (h * 0.022).clamp(11.0, 22.0),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}
