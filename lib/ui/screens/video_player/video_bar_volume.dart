// The round buttons over a video, and the video bar's own volume (0.1.62, up to the volume boost's
// top). Part of video_player_screen.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../video_player_screen.dart';

/// A round, see-through button over a video.
class _OverlayButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _OverlayButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      );
}

/// The video bar's volume on a computer (0.1.62, in place of media_kit's, which stops at 100):
/// the speaker (mute / unmute) and a slider from 0 to 100, or up to the volume boost's top.
/// Above 100 the sound is amplified (models/volume_boost.dart).
class _VideoBarVolume extends StatefulWidget {
  final Player player;
  final double Function() maxVolume;
  final VideoPlayerLook look;
  final Color accent;
  const _VideoBarVolume({required this.player, required this.maxVolume, required this.look, required this.accent});

  @override
  State<_VideoBarVolume> createState() => _VideoBarVolumeState();
}

class _VideoBarVolumeState extends State<_VideoBarVolume> {
  double _beforeMute = 100;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final buttons = widget.look.buttons(widget.accent), track = widget.look.seekTrack(widget.accent);
    // Redrawn as soon as the volume boost is changed in Settings, not only when the volume
    // moves (0.1.70).
    final top = context.select<LibraryModel?, double?>((l) => l?.maxVolume);
    return StreamBuilder<double>(
      stream: p.stream.volume,
      initialData: p.state.volume,
      builder: (context, snap) {
        final max = top ?? widget.maxVolume();
        final volume = sliderVolume(snap.data ?? 100).clamp(0.0, max);
        void set(double v) => p.setVolume(engineVolume(v.clamp(0.0, max)));
        return Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            key: const ValueKey('video-bar-mute'),
            tooltip: volume <= 0 ? 'Unmute' : 'Mute',
            iconSize: widget.look.size.desktop,
            color: buttons,
            icon: Icon(volume <= 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up)),
            onPressed: () {
              if (volume > 0) {
                _beforeMute = volume;
                set(0);
              } else {
                set(_beforeMute <= 0 ? 100 : _beforeMute);
              }
            },
          ),
          SizedBox(
            width: 96,
            child: Tooltip(
              message: 'Volume ${volume.round()}%',
              waitDuration: const Duration(milliseconds: 800),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: buttons,
                  inactiveTrackColor: track,
                  thumbColor: buttons,
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: VolumeSlider(sliderKey: const ValueKey('video-bar-volume'), value: volume, max: max, onChanged: set),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
