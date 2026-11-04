// An example of the subtitle size (4 Nov 2026, the user: "When setting the subtitle size,
// provide a example so that we can see what the size of the subtitles will look like, don't let
// it take up too much space"): a small 16:9 picture, like a paused video, with a line of
// subtitles drawn in the size chosen. Under Settings › Videos › Subtitle size.
//
// The words are sized against the little picture as they will be against the video: the PC's
// engine (mpv) draws subtitles in proportion to the picture's height (`sub-font-size` 55 at
// 720 lines, the text itself about 6 % of the height), times the size setting (`sub-scale`).
// White with a dark outline, as mpv and media_kit draw them.
import 'package:flutter/material.dart';

class SubtitleSizePreview extends StatelessWidget {
  /// The size setting (1.0 = Normal).
  final double size;

  /// The picture's height; it's 16:9.
  final double height;

  const SubtitleSizePreview({super.key, required this.size, this.height = 135});

  /// How tall the subtitle text is next to the picture's height, at Normal.
  static const normalShare = 0.06;

  @override
  Widget build(BuildContext context) {
    final width = height * 16 / 9;
    final font = height * normalShare * size;
    final outline = (font / 9).clamp(0.6, 2.0);
    return Semantics(
      label: 'Example of the subtitle size',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          key: const ValueKey('subtitle-size-preview'),
          width: width,
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            // A plain evening scene, so the white words show as they would over a picture.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2E4A6B), Color(0xFF6B5B73), Color(0xFF3B3430)],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: width * 0.62,
              top: height * 0.16,
              child: Container(
                width: height * 0.16,
                height: height * 0.16,
                decoration: const BoxDecoration(color: Color(0x55FFE9B0), shape: BoxShape.circle),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * 0.3,
              child: const ColoredBox(color: Color(0xFF231F1C)),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: height * 0.05,
              child: Text(
                'Where are you going?\nWherever the road takes us.',
                textAlign: TextAlign.center,
                maxLines: 2,
                softWrap: false,
                overflow: TextOverflow.visible,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: font,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    for (final o in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)])
                      Shadow(color: Colors.black, offset: o * outline, blurRadius: outline),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
