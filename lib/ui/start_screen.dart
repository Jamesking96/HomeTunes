// The screen HomeTunes shows while it opens (0.2.12). The user (8 Nov 2026): "update the TV build
// so that the opening screen isn't just a white screen". Android shows its launch window (the
// app's dark background with the icon in the middle: android/app/src/main/res/drawable/
// launch_background.xml) until Flutter draws its first picture; main.dart then shows this, the
// same picture, at once, while the saved files are read (about 3.5 s on the test TV),
// and swaps in the app when they're ready. If it takes more than a second, "Loading your
// library…" appears under the icon, so a slow start doesn't look stuck.
//
// It runs before the settings are read, so it uses the Default theme's background, the same
// colour as the launch window (res/values/colors.xml).
import 'dart:async';

import 'package:flutter/widgets.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.wordsAfter = const Duration(seconds: 1)});

  /// How long before "Loading your library…" shows.
  final Duration wordsAfter;

  /// The launch window's colour (res/values/colors.xml) and the Default theme's background.
  static const background = Color(0xFF101114);

  /// The icon's size, matching the launch window's (192 pixels in drawable-xhdpi = 96 dp).
  static const logoSize = 96.0;

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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: StartScreen.background,
        child: Stack(children: [
          // In the very middle, as the launch window has it, so nothing jumps.
          Center(
            child: Image.asset(
              'assets/start_logo.png',
              width: StartScreen.logoSize,
              height: StartScreen.logoSize,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'HomeTunes',
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: StartScreen.logoSize + 48),
              child: AnimatedOpacity(
                opacity: _words ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: const Text(
                  'Loading your library…',
                  style: TextStyle(color: Color(0xFFA3A8B3), fontSize: 16, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
