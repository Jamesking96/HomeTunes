// Escape cancels a selection (0.1.48, the user asked: "Make it so pressing escape on the PC
// cancels selection").
//
// Every selection bar (songs, albums and books in shell.dart; collections and videos on the
// Videos tab and a collection's page) is wrapped in an [EscapeCancels]. While the bar is on
// screen, pressing Esc calls [onCancel], the same as the bar's ✕.
//
// It listens on HardwareKeyboard rather than through focus, so it works whatever has focus
// (nothing usually does after clicking a tile). It only acts while its page is the one in front:
// with a dialog or menu open, or a page pushed over it, Esc is left alone. It never marks the
// key as handled, so anything else that uses Esc (leaving full screen in the video player) still
// gets it.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EscapeCancels extends StatefulWidget {
  const EscapeCancels({super.key, required this.onCancel, required this.child});

  final VoidCallback onCancel;
  final Widget child;

  @override
  State<EscapeCancels> createState() => _EscapeCancelsState();
}

class _EscapeCancelsState extends State<EscapeCancels> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape || !mounted) return false;
    if (!_inFront(context)) return false;
    widget.onCancel();
    return false;
  }

  /// True when this page is the top one in its navigator, and so is every navigator it sits in
  /// (a tab's pages are in a navigator of their own; menus and dialogs open on the outer one).
  static bool _inFront(BuildContext context) {
    BuildContext? at = context;
    while (at != null) {
      final route = ModalRoute.of(at);
      if (route == null) return true;
      if (!route.isCurrent) return false;
      at = route.navigator?.context;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
