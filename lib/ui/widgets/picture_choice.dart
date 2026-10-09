// "Change picture…": the list of ways to choose one (refactor phase 6, 9 Oct 2026). Videos,
// collection posters, audiobook series and artists each had their own copy of this dialog; now they
// pass their own choices (same wording, order and keys as before) and get back the one tapped.
import 'package:flutter/material.dart';

import '../theme.dart';

/// One way to choose a picture: an image file, a frame, online, one of the covers, automatic.
class PictureChoice {
  const PictureChoice(this.value, this.icon, this.label, this.detail, {this.enabled = true});
  final String value;
  final IconData icon;
  final String label, detail;
  final bool enabled;
}

/// Shows [choices] under [title]; returns the chosen one's value, or null if closed. Each row's key
/// is `ValueKey('$keyPrefix-${value}')`.
Future<String?> showPictureChoices(
  BuildContext context, {
  required String title,
  required String keyPrefix,
  required List<PictureChoice> choices,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        for (final c in choices)
          SimpleDialogOption(
            key: ValueKey('$keyPrefix-${c.value}'),
            onPressed: c.enabled ? () => Navigator.of(ctx).pop(c.value) : null,
            child: ListTile(
              enabled: c.enabled,
              contentPadding: EdgeInsets.zero,
              leading: Icon(c.icon),
              title: Text(c.label),
              subtitle: Text(c.detail, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
          ),
      ],
    ),
  );
}
