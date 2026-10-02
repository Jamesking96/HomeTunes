// "What's new" (0.1.28): the pop-up shown the first time HomeTunes opens after an update, and
// the "What's new in this version" row on Settings › About.
//
// The text comes from the GitHub release pages: each one starts with "## What's new in x"
// (written by tool/publish_release.ps1 from its -NotesFile). After updating from, say, 0.1.24
// to 0.1.28, every release newer than 0.1.24 up to 0.1.28 is listed, newest first
// (UpdateModel.fetchWhatsNew / releasesSince). If GitHub can't be reached, the pop-up still
// says what version this is and offers the release page. A build that was never published
// (no notes anywhere) shows nothing. Once dealt with, the version is remembered as seen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/update_checker.dart';
import '../../../state/update_model.dart';
import '../../theme.dart';
import '../../widgets/offline_warning.dart';
import 'settings_widgets.dart';
import 'update_ui.dart';

/// Shows "What's new" if this is the first start after an update. Called by main.dart a
/// moment after start-up.
Future<void> showWhatsNewAfterUpdate(UpdateModel updates) async {
  if (!updates.justUpdated) return;
  List<ReleaseInfo>? releases;
  String? problem;
  try {
    releases = await updates.fetchWhatsNew();
  } on UpdateException catch (e) {
    problem = e.message;
  } catch (_) {
    problem = 'The list of changes couldn\'t be loaded.';
  }
  if (releases != null && releases.isEmpty) {
    // Nothing published for this version (e.g. a test build): nothing to show.
    await updates.markWhatsNewSeen();
    return;
  }
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return; // try again next start
  await showWhatsNewDialog(
    context,
    version: updates.currentVersion ?? '',
    from: updates.updatedFrom,
    releases: releases ?? const [],
    problem: problem,
    afterUpdate: true,
  );
  await updates.markWhatsNewSeen();
}

/// The pop-up. [releases] newest first; [problem] says why they couldn't be loaded.
Future<void> showWhatsNewDialog(
  BuildContext context, {
  required String version,
  String? from,
  required List<ReleaseInfo> releases,
  String? problem,
  bool afterUpdate = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => WhatsNewDialog(
        version: version,
        from: from,
        releases: releases,
        problem: problem,
        afterUpdate: afterUpdate,
      ),
    );

class WhatsNewDialog extends StatelessWidget {
  final String version;
  final String? from;
  final List<ReleaseInfo> releases;
  final String? problem;
  final bool afterUpdate;

  const WhatsNewDialog({
    super.key,
    required this.version,
    this.from,
    required this.releases,
    this.problem,
    this.afterUpdate = false,
  });

  @override
  Widget build(BuildContext context) {
    final dim = TextStyle(color: AppColors.textDim, fontSize: 13);
    final heading = TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text);
    final page = releases.isNotEmpty ? releases.first.page : releasesPage;
    final intro = afterUpdate
        ? (from != null
            ? 'HomeTunes has been updated from $from to $version.'
            : 'HomeTunes has been updated to $version.')
        : 'You have HomeTunes $version.';

    return AlertDialog(
      key: const Key('whats-new-dialog'),
      title: Text(afterUpdate ? 'What\'s new in HomeTunes' : 'What\'s new in $version'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 460),
        child: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(intro, style: dim),
            if (problem != null) ...[
              const SizedBox(height: 12),
              Text('The list of changes couldn\'t be loaded. $problem', key: const Key('whats-new-problem')),
              const SizedBox(height: 6),
              Text('You can read it on the release page instead.', style: dim),
            ],
            if (releases.isNotEmpty) ...[
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (i, r) in releases.indexed) ...[
                      if (i > 0) Divider(height: 28, color: AppColors.divider),
                      if (i == 0) const SizedBox(height: 8),
                      Text('Version ${r.version}', style: heading, key: Key('whats-new-version:${r.version}')),
                      const SizedBox(height: 6),
                      NotesText(r.notes),
                    ],
                  ]),
                ),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => UpdateChecker.openInBrowser(page),
          child: const Text('Open release page'),
        ),
        FilledButton(
          key: const Key('whats-new-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// The "What's new in this version" row on Settings › About.
class WhatsNewRow extends StatefulWidget {
  const WhatsNewRow({super.key});

  @override
  State<WhatsNewRow> createState() => _WhatsNewRowState();
}

class _WhatsNewRowState extends State<WhatsNewRow> {
  bool _loading = false;

  Future<void> _open() async {
    final u = context.read<UpdateModel>();
    setState(() => _loading = true);
    // No internet: say so (0.1.50) instead of a list that can't load.
    if (!await ensureOnline(context)) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    List<ReleaseInfo> releases = const [];
    String? problem;
    try {
      releases = await u.fetchWhatsNew(thisVersionOnly: true);
      if (releases.isEmpty) problem = 'There are no release notes for this version on GitHub.';
    } on UpdateException catch (e) {
      problem = e.message;
    } catch (_) {
      problem = 'Something went wrong.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    await showWhatsNewDialog(context, version: u.currentVersion ?? '?', releases: releases, problem: problem);
  }

  @override
  Widget build(BuildContext context) {
    final version = context.select<UpdateModel, String?>((u) => u.currentVersion);
    return SettingTarget(
      'whats-new',
      child: ListTile(
        leading: const Icon(Icons.new_releases_outlined),
        title: const Text('What\'s new in this version'),
        subtitle: Text(version == null ? 'The changes in this version' : 'The changes in HomeTunes $version'),
        trailing: _loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _loading ? null : _open,
      ),
    );
  }
}

/// Release-note text as it's written on the release pages: "- " bullets (indented ones one
/// level in), "#" headings, plain paragraphs, **bold**, `code` and [links](…) shown as text.
class NotesText extends StatelessWidget {
  final String markdown;
  const NotesText(this.markdown, {super.key});

  static final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.text);
    final children = <Widget>[];
    var gap = false;
    for (final raw in markdown.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        gap = children.isNotEmpty;
        continue;
      }
      if (gap) children.add(const SizedBox(height: 6));
      gap = false;
      final h = _heading.firstMatch(line.trim());
      final b = _bullet.firstMatch(line);
      final n = _numbered.firstMatch(line);
      if (h != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Text.rich(inlineSpans(h.group(1)!, base.copyWith(fontWeight: FontWeight.w700))),
        ));
      } else if (b != null || n != null) {
        final indent = ((b ?? n)!.group(1)!.replaceAll('\t', '  ').length ~/ 2).clamp(0, 3);
        final marker = b != null ? (indent == 0 ? '•' : '◦') : '${n!.group(2)}.';
        final text = b != null ? b.group(2)! : n!.group(3)!;
        children.add(Padding(
          padding: EdgeInsets.only(left: 4.0 + indent * 18, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 16, child: Text(marker, style: base.copyWith(color: AppColors.accent))),
            Expanded(child: Text.rich(inlineSpans(text, base))),
          ]),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(inlineSpans(line.trim(), base)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

/// One line of release-note text as styled pieces: **bold** in bold, `code` and [link](url)
/// markup removed.
TextSpan inlineSpans(String text, TextStyle style) {
  final plain = text
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAll('`', '');
  final parts = plain.split('**');
  return TextSpan(style: style, children: [
    for (final (i, part) in parts.indexed)
      if (part.isNotEmpty)
        // Odd pieces sat between a pair of ** marks. An unpaired ** at the end is shown plain.
        TextSpan(
          text: part,
          style: i.isOdd && i < parts.length - (parts.length.isEven ? 1 : 0)
              ? const TextStyle(fontWeight: FontWeight.w700)
              : null,
        ),
  ]);
}
