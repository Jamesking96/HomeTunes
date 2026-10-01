// Settings › Appearance › Video player (0.1.40): the colour and size of the video
// player's buttons, the seek bar's colour, and what goes behind the buttons so they
// can be seen over a black (or white) picture. A preview shows the bar over a dark,
// bright or busy scene. Saved in settings.json as videoPlayerLook.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/video_player_look.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import '../../widgets/video_controls_look.dart';
import 'appearance_settings.dart' show showColourPicker, PickerMode;
import 'settings_widgets.dart';

/// The colour choices offered as chips; anything else is "Your own".
const _buttonColours = [('white', 'White'), ('accent', 'Theme highlight'), ('black', 'Black')];
const _seekColours = [('accent', 'Theme highlight'), ('red', 'Red'), ('white', 'White')];

class VideoPlayerLookSettings extends StatefulWidget {
  const VideoPlayerLookSettings({super.key});

  @override
  State<VideoPlayerLookSettings> createState() => _VideoPlayerLookSettingsState();
}

class _VideoPlayerLookSettingsState extends State<VideoPlayerLookSettings> {
  PreviewScene _scene = PreviewScene.dark;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final look = lib.videoPlayerLook;
    final accent = AppColors.accent;
    void set(VideoPlayerLook l) => lib.setVideoPlayerLook(l);
    final dim = TextStyle(color: AppColors.textDim, fontSize: 12);

    Widget colourRow({
      required String keyPrefix,
      required String current,
      required List<(String, String)> options,
      required String pickerTitle,
      required ValueChanged<String> onChanged,
    }) {
      final own = !options.any((o) => o.$1 == current);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              key: ValueKey('$keyPrefix-${o.$1}'),
              avatar: CircleAvatar(backgroundColor: resolveLookColour(o.$1, accent), radius: 8),
              label: Text(o.$2),
              selected: current == o.$1,
              onSelected: (_) => onChanged(o.$1),
            ),
          ChoiceChip(
            key: ValueKey('$keyPrefix-own'),
            avatar: own
                ? CircleAvatar(backgroundColor: resolveLookColour(current, accent), radius: 8)
                : const Icon(Icons.palette_outlined, size: 18),
            label: const Text('Your own…'),
            selected: own,
            onSelected: (_) async {
              final c = await showColourPicker(
                context,
                title: pickerTitle,
                initial: resolveLookColour(current, accent),
                mode: PickerMode.any,
              );
              if (c != null) onChanged(colourToHex(c));
            },
          ),
        ],
      );
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsGroupTitle('Video player', 'The buttons over the picture while a video plays'),
        SettingTarget(
          'video-player-preview',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: VideoControlsPreview(
                    key: const ValueKey('video-look-preview'),
                    look: look,
                    accent: accent,
                    scene: _scene,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<PreviewScene>(
                  key: const ValueKey('preview-scene'),
                  showSelectedIcon: false,
                  segments: [for (final s in PreviewScene.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {_scene},
                  onSelectionChanged: (s) => setState(() => _scene = s.first),
                ),
                const SizedBox(height: 4),
                Text('Try each scene: the buttons should be easy to see over all three.', style: dim),
              ],
            ),
          ),
        ),
        SettingTarget(
          'video-button-colour',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Button colour'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: colourRow(
                  keyPrefix: 'button-colour',
                  current: look.buttonColour,
                  options: _buttonColours,
                  pickerTitle: 'Button colour',
                  onChanged: (c) => set(look.copyWith(buttonColour: c)),
                ),
              ),
            ],
          ),
        ),
        SettingTarget(
          'video-button-size',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Button size'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<VideoButtonSize>(
                  key: const ValueKey('button-size'),
                  showSelectedIcon: false,
                  segments: [for (final s in VideoButtonSize.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {look.size},
                  onSelectionChanged: (s) => set(look.copyWith(size: s.first)),
                ),
              ),
            ],
          ),
        ),
        SettingTarget(
          'video-button-backing',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Behind the buttons'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<VideoButtonBacking>(
                  key: const ValueKey('button-backing'),
                  showSelectedIcon: false,
                  segments: [for (final b in VideoButtonBacking.values) ButtonSegment(value: b, label: Text(b.label))],
                  selected: {look.backing},
                  onSelectionChanged: (s) => set(look.copyWith(backing: s.first)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'A shade behind each button keeps it readable when the picture is the same colour. '
                  'It\'s dark behind light buttons and light behind dark ones.',
                  style: dim,
                ),
              ),
              if (look.backing != VideoButtonBacking.none)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Text('Strength'),
                      Expanded(
                        child: Slider(
                          key: const ValueKey('backing-strength'),
                          min: 0.2,
                          max: 0.9,
                          divisions: 7,
                          value: look.backingStrength.clamp(0.2, 0.9),
                          label: '${(look.backingStrength * 100).round()}%',
                          onChanged: (v) => set(look.copyWith(backingStrength: (v * 10).round() / 10)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SettingTarget(
          'video-seek-colour',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Progress bar colour'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: colourRow(
                  keyPrefix: 'seek-colour',
                  current: look.seekColour,
                  options: _seekColours,
                  pickerTitle: 'Progress bar colour',
                  onChanged: (c) => set(look.copyWith(seekColour: c)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: TextButton.icon(
            key: const ValueKey('video-look-reset'),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset the video player look'),
            onPressed: look == VideoPlayerLook.standard ? null : () => set(VideoPlayerLook.standard),
          ),
        ),
      ],
    );
  }
}
