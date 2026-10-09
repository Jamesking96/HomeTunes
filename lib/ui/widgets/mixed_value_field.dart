// A box for a detail that differs across the songs, albums or books being edited together
// (refactor phase 6, 9 Oct 2026; the screen side of state/mixed_value.dart). The song / album and
// book editors each built this themselves: the box shows --:-- (its label stays up), the line under
// it says what leaving it does, and once something is typed a ↶ button offers "keep each one's own".
// Boxes where they all agree use the editor's own helper line and button.
import 'package:flutter/material.dart';

import '../../state/mixed_value.dart';
import '../theme.dart';

/// The decoration for one box in an editor for several [noun]s ('song', 'album', 'book').
/// [mixed]: they differ here. [typed]: something is in the box. [onKeepEach] empties it (null while
/// saving). [helper] and [suffix] are the editor's own, used when the --:-- ones don't apply.
InputDecoration mixedValueDecoration({
  required String label,
  required bool mixed,
  required bool typed,
  required String noun,
  required VoidCallback? onKeepEach,
  String? helper,
  Widget? suffix,
}) {
  final what = label.toLowerCase();
  return InputDecoration(
    labelText: label,
    floatingLabelBehavior: mixed ? FloatingLabelBehavior.always : null,
    hintText: mixed ? differentMarker : null,
    hintStyle: mixed ? TextStyle(color: AppColors.textDim, letterSpacing: 2, fontWeight: FontWeight.w600) : null,
    helperText: mixed
        ? (typed ? 'Every $noun gets this $what' : 'Different for each $noun – leave as $differentMarker to keep them')
        : helper,
    suffixIcon: mixed && typed
        ? IconButton(
            tooltip: 'Keep each $noun\'s own $what',
            icon: const Icon(Icons.undo, size: 20),
            onPressed: onKeepEach,
          )
        : suffix,
  );
}
