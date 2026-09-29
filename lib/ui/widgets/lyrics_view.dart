// The lyrics panel shown in Now Playing (and from the desktop player bar).
//
// LyricsModel decides where the lyrics come from (your own, the file, saved, server, LRCLIB);
// this widget asks it for them, then shows one of: "Looking…", a "no lyrics" message with
// buttons, plain text, or timed lines that light up and scroll along with the song. A small
// footer says where the lyrics came from and has a menu (find, edit, hide, look again).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/lyrics.dart';
import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/lyrics_model.dart';
import '../../state/player_model.dart';
import '../screens/lyrics_dialogs.dart';
import '../theme.dart';

/// A song's lyrics. When [track] is the song playing and the lyrics are
/// timed, the current line is highlighted and kept in view, and tapping a
/// line jumps there.
class LyricsView extends StatefulWidget {
  final Track track;

  /// Bigger text for the full Now Playing view.
  final bool large;
  const LyricsView({super.key, required this.track, this.large = true});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  // The lookup is kept between rebuilds so we don't search again on every redraw; the key
  // records what it was for (see _lyrics).
  Future<Lyrics?>? _future;
  String? _futureKey;

  Future<Lyrics?> _lyrics(LyricsModel model, String? edit) {
    // Look again when the song or the user's lyrics change.
    final key = '${widget.track.id}|$edit|${model.revision}';
    if (key != _futureKey) {
      _futureKey = key;
      _future = model.lyricsFor(widget.track);
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<LyricsModel>();
    // The user's own lyrics live in LibraryModel's edits, so watch those too.
    final edit = context.select<LibraryModel, String?>((l) => l.lyricsEdit(widget.track.id));
    return FutureBuilder<Lyrics?>(
      future: _lyrics(model, edit),
      builder: (context, snap) {
        // Pick what to show in the main area, then add the footer underneath.
        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const _Message(icon: null, text: 'Looking for lyrics…');
        } else if (snap.data == null) {
          body = _NoLyrics(track: widget.track, hidden: model.isHidden(widget.track));
        } else if (snap.data!.timed) {
          // The key restarts the timed view (and its line positions) when the lyrics change.
          body = _TimedLyrics(key: ValueKey(_futureKey), track: widget.track, lyrics: snap.data!, large: widget.large);
        } else {
          body = _PlainLyrics(lyrics: snap.data!, large: widget.large);
        }
        return Column(children: [
          Expanded(child: body),
          _Footer(track: widget.track, lyrics: snap.connectionState == ConnectionState.done ? snap.data : null),
        ]);
      },
    );
  }
}

/// A centred message with an icon (or a spinner when [icon] is null) and optional buttons.
class _Message extends StatelessWidget {
  final IconData? icon;
  final String text;
  final List<Widget> actions;
  const _Message({required this.icon, required this.text, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 40, color: AppColors.textDim) else const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
          ],
        ]),
      ),
    );
  }
}

/// Shown when there are no lyrics: either the user hid them (offer to show again), or none
/// were found (offer to search LRCLIB or type them in).
class _NoLyrics extends StatelessWidget {
  final Track track;
  final bool hidden;
  const _NoLyrics({required this.track, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final model = context.read<LyricsModel>();
    if (hidden) {
      return _Message(
        icon: Icons.lyrics_outlined,
        text: 'You\'ve hidden the lyrics for this song.',
        actions: [OutlinedButton(onPressed: () => model.removeYours(track), child: const Text('Show lyrics again'))],
      );
    }
    final online = context.select<LibraryModel, bool>((l) => l.onlineLyrics);
    return _Message(
      icon: Icons.lyrics_outlined,
      // For a local song with online lookups off, explain why nothing was searched.
      text: online || !track.isLocal
          ? 'No lyrics found for this song.'
          : 'This song has no lyrics of its own.\nLooking them up online is switched off in Settings › Online lookups.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => findLyricsOnline(context, track),
          icon: const Icon(Icons.travel_explore, size: 18),
          label: const Text('Find on LRCLIB'),
        ),
        OutlinedButton.icon(
          onPressed: () => editLyrics(context, track),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Add lyrics'),
        ),
      ],
    );
  }
}

/// Where the lyrics came from, and what can be done with them.
class _Footer extends StatelessWidget {
  final Track track;
  final Lyrics? lyrics;
  const _Footer({required this.track, required this.lyrics});

  @override
  Widget build(BuildContext context) {
    final model = context.read<LyricsModel>();
    final l = lyrics;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(children: [
        Expanded(
          child: Text(
            l == null ? '' : '${l.source.label}${l.timed ? ' · timed' : ''}',
            style: TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
        ),
        // Each menu item's value is the action to run, so onSelected just calls it.
        // Items only appear when they make sense for these lyrics.
        PopupMenuButton<VoidCallback>(
          tooltip: 'Lyrics options',
          icon: Icon(Icons.more_horiz, color: AppColors.textDim),
          onSelected: (f) => f(),
          itemBuilder: (_) => [
            PopupMenuItem(value: () => findLyricsOnline(context, track), child: const Text('Find lyrics on LRCLIB…')),
            PopupMenuItem(value: () => editLyrics(context, track), child: Text(l == null ? 'Add lyrics…' : 'Edit lyrics…')),
            if (l != null && l.source != LyricsSource.yours)
              PopupMenuItem(value: () => model.hide(track), child: const Text('Hide lyrics for this song')),
            if (model.hasYours(track))
              PopupMenuItem(
                value: () => model.removeYours(track),
                child: const Text('Remove your lyrics'),
              ),
            if (l != null && (l.source == LyricsSource.lrclib || l.source == LyricsSource.server))
              PopupMenuItem(value: () => model.forget(track), child: const Text('Look again')),
          ],
        ),
      ]),
    );
  }
}

/// Untimed lyrics: one block of selectable text (so it can be copied).
class _PlainLyrics extends StatelessWidget {
  final Lyrics lyrics;
  final bool large;
  const _PlainLyrics({required this.lyrics, required this.large});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        SelectableText(
          lyrics.lines.map((l) => l.text).join('\n'),
          style: TextStyle(fontSize: large ? 20 : 16, height: 1.6, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Timed (LRC) lyrics that follow the song: the current line is bright, sung lines dimmer,
/// upcoming ones dimmest.
class _TimedLyrics extends StatefulWidget {
  final Track track;
  final Lyrics lyrics;
  final bool large;
  const _TimedLyrics({super.key, required this.track, required this.lyrics, required this.large});

  @override
  State<_TimedLyrics> createState() => _TimedLyricsState();
}

class _TimedLyricsState extends State<_TimedLyrics> {
  final _scroll = ScrollController();
  // One key per line so we can find a line on screen and scroll to it.
  late final List<GlobalKey> _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  StreamSubscription<Duration>? _sub;
  int _current = -1; // index of the line being sung, -1 = before the first line

  /// After the user scrolls by hand, leave the view alone for a moment.
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  PlayerModel get _player => context.read<PlayerModel>();
  /// Only follow along when this song is the one playing (the view can show another song).
  bool get _isPlaying => _player.current?.id == widget.track.id;

  @override
  void initState() {
    super.initState();
    // Wait for the first frame so the lines exist, then follow the position and jump
    // (no animation) straight to the current line.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sub = _player.positionStream.listen(_onPosition);
      _onPosition(_player.position, jump: true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Called on every position update. Only redraws when the current line actually changes.
  void _onPosition(Duration pos, {bool jump = false}) {
    if (!mounted || !_isPlaying) return;
    final i = widget.lyrics.lineAt(pos);
    if (i == _current) return;
    setState(() => _current = i);
    // The user scrolled in the last 4 seconds: highlight, but don't pull the view away.
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    final ctx = i >= 0 ? _keys[i].currentContext : null;
    if (ctx != null) {
      // Put the current line about a third of the way down, so some upcoming lines show too.
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: jump ? Duration.zero : const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else if (i < 0 && _scroll.hasClients) {
      // Before the first line (e.g. after seeking back to the start): go to the top.
      _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    final size = widget.large ? 24.0 : 18.0;
    final playing = context.select<PlayerModel, bool>((p) => p.current?.id == widget.track.id);
    // Note when the user scrolls by hand, so auto-scroll backs off for a while.
    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      // Every line is built (lyrics are short), so each can be scrolled to.
      child: SingleChildScrollView(
        controller: _scroll,
        // Big bottom padding lets the last lines scroll up to the reading position.
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 200),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < lines.length; i++)
            InkWell(
              key: _keys[i],
              borderRadius: AppShape.circular(6),
              onTap: playing
                  ? () {
                      // Tapping a line seeks there and turns auto-scroll straight back on.
                      _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);
                      _player.seek(lines[i].time!);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: size,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: !playing || i == _current
                        ? AppColors.text
                        : (i < _current ? AppColors.faded(0.54) : AppColors.faded(0.38)),
                  ),
                  // An empty timed line is a pause in the singing.
                  child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
