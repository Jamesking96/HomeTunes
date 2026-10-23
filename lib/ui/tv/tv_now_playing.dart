// The TV's Now Playing (0.2.0, step 5 of the TV interface; mockup "Now Playing"), for songs and
// audiobooks. The cover big on the left over a blurred copy of itself; on the right what's
// playing, the progress bar (TvSeekBar: ← → move through it, OK jumps), the buttons, and a row
// of extras:
//  * songs: Shuffle, Previous, Play / Pause, Next, Repeat; then Up next (the queue in a panel,
//    OK plays from there), Lyrics (a panel), the heart, Volume − / +, Sleep timer;
//  * audiobooks: Previous chapter, Back, Play / Pause, Forward, Next chapter; then Chapters (a
//    panel), Bookmark, Speed − / +, Volume − / +, Sleep timer, and Back to music when music is
//    waiting.
// Play / Pause has focus when it opens. Back closes it (or puts the bar's marker away first).
// It reads PlayerModel like the usual Now Playing; music videos aren't shown here.
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/player_model.dart';
import '../../state/play_queue.dart' show RepeatSetting;
import '../../state/playlists_model.dart';
import '../../state/sleep_timer.dart';
import '../../state/settings/settings_groups.dart' as prefs;
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/bookmark_widgets.dart' show addBookmarkNow;
import '../widgets/lyrics_view.dart';
import 'tv_browse.dart';
import 'tv_detail.dart' show TvIconButton;
import 'tv_options.dart';
import 'tv_seek_bar.dart';
import 'tv_widgets.dart';

/// Opens Now Playing over everything.
void openTvNowPlaying(BuildContext context) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      pageBuilder: (_, _, _) => const TvNowPlayingPage(),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    ));

class TvNowPlayingPage extends StatefulWidget {
  const TvNowPlayingPage({super.key});

  @override
  State<TvNowPlayingPage> createState() => _TvNowPlayingPageState();
}

class _TvNowPlayingPageState extends State<TvNowPlayingPage> {
  final _bar = TvSeekBarController();

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final t = player.current;
    return PopScope(
      canPop: !_bar.scrubbing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _bar.cancel();
      },
      child: ListenableBuilder(
        listenable: _bar,
        builder: (context, _) => Scaffold(
          backgroundColor: AppColors.bg,
          body: t == null ? _nothing() : _playing(context, player, t),
        ),
      ),
    );
  }

  Widget _nothing() => const Stack(children: [
        TvEmpty(icon: Icons.music_note_outlined, title: 'Nothing is playing'),
        Positioned(right: 24, bottom: 16, child: TvHints([('Back', 'close')])),
      ]);

  Widget _playing(BuildContext context, PlayerModel player, Track t) {
    final book = player.book;
    final from = player.queue.contextLabel;
    final kind = book != null
        ? 'AUDIOBOOK · ${book.title}'
        : from == null
            ? 'NOW PLAYING'
            : 'NOW PLAYING · FROM ${(from.contains(' · ') ? from.substring(from.indexOf(' · ') + 3) : from).toUpperCase()}';
    final title = book != null ? (player.currentChapter?.title ?? t.title) : t.title;
    final subtitle = book != null ? book.author : t.artist;

    return Stack(children: [
      // The cover, blurred and dimmed, behind everything.
      Positioned.fill(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Opacity(opacity: 0.45, child: FittedBox(fit: BoxFit.cover, child: Artwork(track: t, size: 400, radius: 0))),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.35), AppColors.bg.withValues(alpha: 0.85)]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(56, 48, 56, 56),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Artwork(track: book?.artTrack ?? t, size: 300, radius: 0, placeholder: book != null ? Icons.menu_book : Icons.music_note),
          ),
          const SizedBox(width: 48),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(kind, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w600, color: AppColors.textDim)),
              const SizedBox(height: 6),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, color: AppColors.text)),
              const SizedBox(height: 24),
              TvSeekBar(
                key: const ValueKey('tv-np-bar'),
                controller: _bar,
                position: () => player.position,
                length: () => player.duration,
                positions: player.positionStream,
                onSeek: player.seek,
                onActivate: player.togglePlay,
              ),
              const SizedBox(height: 18),
              _transport(context, player),
              const SizedBox(height: 22),
              _extras(context, player, t),
            ]),
          ),
        ]),
      ),
      Positioned(
        right: 24,
        bottom: 16,
        child: TvHints([('← →', book != null ? 'on the bar: move through the chapter' : 'on the bar: move through the song'), ('Back', 'close')]),
      ),
    ]);
  }

  Widget _transport(BuildContext context, PlayerModel player) {
    final book = player.book != null;
    final listening = context.watch<prefs.ListeningSettings>();
    Widget round(IconData icon, String label, VoidCallback? onPressed, {bool on = false, Key? key}) =>
        _RoundButton(key: key, icon: icon, label: label, onPressed: onPressed, on: on);
    return Row(children: [
      if (book) ...[
        round(Icons.skip_previous_rounded, 'Previous chapter', player.previousChapter),
        const SizedBox(width: 14),
        round(Icons.replay, 'Back ${listening.skipBackSeconds} seconds', player.skipBack),
      ] else ...[
        round(Icons.shuffle, player.shuffle ? 'Shuffle is on' : 'Shuffle', player.toggleShuffle, on: player.shuffle),
        const SizedBox(width: 14),
        round(Icons.skip_previous_rounded, 'Previous', player.previous),
      ],
      const SizedBox(width: 14),
      _RoundButton(
        key: const ValueKey('tv-np-play'),
        icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        label: player.playing ? 'Pause' : 'Play',
        onPressed: player.togglePlay,
        big: true,
        autofocus: true,
      ),
      const SizedBox(width: 14),
      if (book) ...[
        round(Icons.forward_30, 'Forward ${listening.skipForwardSeconds} seconds', player.skipForward),
        const SizedBox(width: 14),
        round(Icons.skip_next_rounded, 'Next chapter', player.nextChapter),
      ] else ...[
        round(Icons.skip_next_rounded, 'Next', player.next),
        const SizedBox(width: 14),
        round(player.repeat == RepeatSetting.one ? Icons.repeat_one : Icons.repeat, switch (player.repeat) {
          RepeatSetting.off => 'Repeat',
          RepeatSetting.all => 'Repeat is on',
          RepeatSetting.one => 'Repeating this song',
        }, player.cycleRepeat, on: player.repeat != RepeatSetting.off),
      ],
    ]);
  }

  Widget _extras(BuildContext context, PlayerModel player, Track t) {
    final book = player.book;
    final pl = context.watch<PlaylistsModel>();
    final liked = pl.isLiked(t);
    final maxVolume = context.select<prefs.PlaybackSettings, double>((s) => s.maxVolume);
    final volume = player.volume;
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (book == null) ...[
        TvButton(key: const ValueKey('tv-np-up-next'), label: 'Up next', icon: Icons.queue_music, onPressed: () => showTvUpNext(context)),
        TvButton(key: const ValueKey('tv-np-lyrics'), label: 'Lyrics', icon: Icons.lyrics_outlined, onPressed: () => showTvLyrics(context, t)),
        TvIconButton(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          label: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
          on: liked,
          onPressed: () => pl.toggleLike(t),
        ),
      ] else ...[
        TvButton(key: const ValueKey('tv-np-chapters'), label: 'Chapters', icon: Icons.list, onPressed: () => showTvChapters(context)),
        TvButton(label: 'Bookmark', icon: Icons.bookmark_add_outlined, onPressed: () => addBookmarkNow(context)),
        TvStepper(
          label: 'Speed ${_speed(player.speed)}',
          onLess: player.speed <= 0.5 ? null : () => player.setSpeed(((player.speed - 0.1) * 10).round() / 10),
          onMore: player.speed >= 3.0 ? null : () => player.setSpeed(((player.speed + 0.1) * 10).round() / 10),
          lessLabel: 'Slower',
          moreLabel: 'Faster',
        ),
      ],
      TvStepper(
        key: const ValueKey('tv-np-volume'),
        label: 'Volume ${volume.round()}%',
        onLess: volume <= 0 ? null : () => player.setVolume((volume - 5).clamp(0, maxVolume)),
        onMore: volume >= maxVolume ? null : () => player.setVolume((volume + 5).clamp(0, maxVolume)),
        lessLabel: 'Quieter',
        moreLabel: 'Louder',
      ),
      const TvSleepButton(),
      if (book != null && player.hasWaitingMusic)
        TvButton(label: 'Back to music', icon: Icons.music_note, onPressed: player.resumeMusic),
    ]);
  }

  static String _speed(double s) => '${s.toStringAsFixed(s == s.roundToDouble() ? 1 : (s * 10 == (s * 10).roundToDouble() ? 1 : 2))}×';
}

/// A round transport button (Previous, Play / Pause, Next…); [on] marks Shuffle / Repeat in use.
class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.label, required this.onPressed, this.on = false, this.big = false, this.autofocus = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool on, big, autofocus;

  @override
  Widget build(BuildContext context) {
    final size = big ? 72.0 : 52.0;
    return TvPressable(
      onPressed: onPressed,
      autofocus: autofocus,
      semanticLabel: label,
      builder: (context, focused) => TvFocusFrame(
        focused: focused,
        radius: size,
        child: Container(
          width: size,
          height: size,
          color: big ? Colors.white : (focused ? Colors.white : Colors.white.withValues(alpha: 0.08)),
          child: Icon(icon,
              size: big ? 40 : 26,
              color: big || focused ? const Color(0xFF16202B) : (on ? AppColors.accent : Colors.white)),
        ),
      ),
    );
  }
}

/// − [label] +: a value the remote steps up and down (volume, speed). No slider on a TV.
class TvStepper extends StatelessWidget {
  const TvStepper({super.key, required this.label, required this.onLess, required this.onMore, this.lessLabel = 'Less', this.moreLabel = 'More'});
  final String label, lessLabel, moreLabel;
  final VoidCallback? onLess, onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: AppColors.surfaceHigh.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        TvIconButton(icon: Icons.remove, label: lessLabel, onPressed: onLess),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        TvIconButton(icon: Icons.add, label: moreLabel, onPressed: onMore),
      ]),
    );
  }
}

/// The sleep timer: off, it starts with Settings › Sleep timer's length; on, it shows the time
/// left and stops it.
class TvSleepButton extends StatelessWidget {
  const TvSleepButton({super.key});

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<SleepTimer>();
    final hasTrack = context.select<PlayerModel, bool>((p) => p.current != null);
    if (!timer.active) {
      return TvButton(key: const ValueKey('tv-sleep'), label: 'Sleep timer', icon: Icons.bedtime_outlined, onPressed: hasTrack ? timer.start : null);
    }
    final left = timer.remaining;
    return TvButton(
      key: const ValueKey('tv-sleep'),
      label: left == null ? 'Sleep timer on' : 'Sleep in ${tvTime(left)}',
      icon: Icons.bedtime,
      primary: true,
      onPressed: timer.cancel,
    );
  }
}

/// Up next: the songs still to come, in the options panel. OK plays from that one; holding OK is
/// not needed (the queue's own moves wait for a later step).
Future<void> showTvUpNext(BuildContext context) {
  final player = context.read<PlayerModel>();
  final q = player.queue;
  final start = q.position + 1;
  final upcoming = [for (var i = start; i < q.tracks.length && i < start + 60; i++) (i, q.tracks[i])];
  return showTvOptions(context, title: 'Up next', subtitle: upcoming.isEmpty ? 'Nothing after this song' : '${q.tracks.length - start} to come', options: [
    for (final (i, t) in upcoming)
      TvOption(t.title, Icons.music_note, subtitle: t.artist, picture: Artwork(track: t, size: 36, radius: 0), () => player.jumpTo(i)),
    if (upcoming.isEmpty) TvOption('Close', Icons.close, () {}),
  ]);
}

/// A book's chapters in the options panel, the one playing first; OK goes there.
Future<void> showTvChapters(BuildContext context) {
  final player = context.read<PlayerModel>();
  final chapters = player.chapters;
  final current = player.currentChapterIndex;
  return showTvOptions(context, title: 'Chapters', subtitle: player.book?.title, focusIndex: current < 0 ? 0 : current, options: [
    for (var i = 0; i < chapters.length; i++)
      TvOption(chapters[i].title, i == current ? Icons.graphic_eq : Icons.bookmark_outline,
          subtitle: 'Starts at ${tvTime(chapters[i].offset)}', () => player.goToChapter(i)),
  ]);
}

/// The song's lyrics in a panel from the right; Back closes it.
Future<void> showTvLyrics(BuildContext context, Track t) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close the lyrics',
      barrierColor: const Color(0xA8050608),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: AppColors.surface,
          child: SizedBox(
            width: 520,
            height: double.infinity,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textDim)),
                const SizedBox(height: 14),
                Expanded(child: Focus(autofocus: true, child: LyricsView(key: ValueKey(t.id), track: t))),
                const SizedBox(height: 8),
                Text.rich(TextSpan(style: TextStyle(fontSize: 12, color: AppColors.textDim), children: const [
                  TextSpan(text: 'Back', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  TextSpan(text: ' closes the lyrics'),
                ])),
              ]),
            ),
          ),
        ),
      ),
      transitionBuilder: (context, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
