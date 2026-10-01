// Titles you can highlight and copy (0.1.41, user's request: "titles of all medias should be
// highlightable to copy and paste").
//
// [SelectableTitle] is used for the big title on each page (album, artist, playlist, book,
// Now Playing, a video collection, a video): drag across it (or double-click a word) and copy
// with Ctrl+C or the right-click menu. It keeps a plain Text inside a SelectionArea, so long
// titles still end in "…" where the page only has room for one or two lines.
// Titles on cards and list rows stay tap-to-open; their menus have "Copy title" ([copyTitle]).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SelectableTitle extends StatelessWidget {
  const SelectableTitle(this.text, {super.key, this.style, this.maxLines, this.textAlign});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => SelectionArea(
        child: Text(
          text,
          style: style,
          maxLines: maxLines,
          textAlign: textAlign,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        ),
      );
}

/// Puts [text] on the clipboard and says so.
Future<void> copyTitle(BuildContext context, String text) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger?.showSnackBar(SnackBar(content: Text('Copied "$text"'), duration: const Duration(seconds: 2)));
}

/// The "Copy title" entry for the menus built with PopupMenuItem.
PopupMenuItem<T> copyTitleMenuItem<T>(T value) => PopupMenuItem<T>(
      key: const ValueKey('copy-title'),
      value: value,
      child: const ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.content_copy),
        title: Text('Copy title'),
      ),
    );
