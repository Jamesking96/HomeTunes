// The notices at the bottom of the screen (snack bars) for the whole app (1 Oct, user's request).
//
// Every notice gets 15 seconds from the moment something asks for it, whether it's on screen yet
// or still waiting behind another one; after that it closes, or is dropped without ever showing.
// Before, a notice with a button (Undo, Start over…) stayed until closed by hand, and everything
// raised meanwhile queued up behind it and came out one by one long after it mattered. The same
// words raised again while already showing or waiting aren't queued twice.
//
// NoticeMessenger replaces the app's ScaffoldMessenger (main.dart puts it in MaterialApp.builder,
// with appMessengerKey), so ScaffoldMessenger.of(context).showSnackBar everywhere goes through it.
import 'dart:async';

import 'package:flutter/material.dart';

class NoticeMessenger extends ScaffoldMessenger {
  const NoticeMessenger({super.key, required super.child});

  @override
  NoticeMessengerState createState() => NoticeMessengerState();
}

class _Notice {
  _Notice(this.bar, this.style);
  final SnackBar bar;
  final AnimationStyle? style;
  Timer? life;
}

class NoticeMessengerState extends ScaffoldMessengerState {
  /// How long a notice lives, counted from when it's asked for.
  static const lifetime = Duration(seconds: 15);

  final List<_Notice> _waiting = [];
  _Notice? _shown;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;

  /// Notices waiting behind the one on screen (tests).
  int get waitingCount => _waiting.length;

  static String? _words(SnackBar bar) {
    final c = bar.content;
    return c is Text ? (c.data ?? c.textSpan?.toPlainText()) : null;
  }

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final current = _controller;
    final words = _words(snackBar);
    if (current != null && words != null) {
      final same = [?_shown, ..._waiting].any((n) => _words(n.bar) == words);
      if (same) return current;
    }
    final notice = _Notice(snackBar, snackBarAnimationStyle);
    notice.life = Timer(lifetime, () => _expire(notice));
    if (current == null) return _show(notice);
    _waiting.add(notice);
    // Nothing to hand back for a notice that isn't on screen yet; nobody in the app uses it.
    return current;
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(_Notice notice) {
    final bar = notice.bar;
    // Notices with a button used to stay until closed; now they last their 15 seconds.
    final shownFor = bar.persist || bar.duration > lifetime ? lifetime : bar.duration;
    final c = super.showSnackBar(
      SnackBar(
        key: bar.key,
        content: bar.content,
        backgroundColor: bar.backgroundColor,
        elevation: bar.elevation,
        margin: bar.margin,
        padding: bar.padding,
        width: bar.width,
        shape: bar.shape,
        hitTestBehavior: bar.hitTestBehavior,
        behavior: bar.behavior,
        action: bar.action,
        actionOverflowThreshold: bar.actionOverflowThreshold,
        showCloseIcon: bar.showCloseIcon,
        closeIconColor: bar.closeIconColor,
        duration: shownFor,
        persist: false,
        animation: bar.animation,
        onVisible: bar.onVisible,
        dismissDirection: bar.dismissDirection,
        clipBehavior: bar.clipBehavior,
      ),
      snackBarAnimationStyle: notice.style,
    );
    _shown = notice;
    _controller = c;
    c.closed.whenComplete(() {
      if (!identical(_controller, c)) return;
      notice.life?.cancel();
      _shown = null;
      _controller = null;
      if (mounted) _showNext();
    });
    return c;
  }

  void _showNext() {
    if (_waiting.isNotEmpty) _show(_waiting.removeAt(0));
  }

  /// A notice's 15 seconds are up: close it if it's showing, else drop it unseen.
  void _expire(_Notice notice) {
    if (!mounted) return;
    if (identical(notice, _shown)) {
      hideCurrentSnackBar(reason: SnackBarClosedReason.timeout);
    } else {
      _waiting.remove(notice);
    }
  }

  @override
  void clearSnackBars() {
    for (final n in _waiting) {
      n.life?.cancel();
    }
    _waiting.clear();
    super.clearSnackBars();
  }

  @override
  void dispose() {
    for (final n in [?_shown, ..._waiting]) {
      n.life?.cancel();
    }
    super.dispose();
  }
}
