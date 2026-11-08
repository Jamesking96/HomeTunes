// Pieces of Profiles (phase 1) used on several screens: a profile's circle, the list of pictures
// and colours to choose from, the add / change dialog, the switcher and switching itself.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/profiles_model.dart';
import '../screens/settings/update_ui.dart' show appNavigatorKey;
import '../theme.dart';

/// The profiles, or null (tests and previews that don't provide them). Watches when [listen].
ProfilesModel? profilesOf(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<ProfilesModel?>(context, listen: listen);
  } on ProviderNotFoundException {
    return null;
  }
}

/// The pictures a profile's circle can show, by the name saved in profiles.json.
const profileIcons = <String, IconData>{
  'person': Icons.person,
  'headphones': Icons.headphones,
  'music': Icons.music_note,
  'book': Icons.menu_book,
  'movie': Icons.movie,
  'star': Icons.star,
  'heart': Icons.favorite,
  'pets': Icons.pets,
  'rocket': Icons.rocket_launch,
  'game': Icons.sports_esports,
  'flower': Icons.local_florist,
  'sun': Icons.wb_sunny,
};

IconData profileIcon(String name) => profileIcons[name] ?? Icons.person;

/// A profile's circle: its colour with its picture.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, this.size = 40});
  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = Color(profile.colour);
    final dark = ThemeData.estimateBrightnessForColor(colour) == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(profileIcon(profile.icon), size: size * 0.55, color: dark ? Colors.white : Colors.black87),
    );
  }
}

/// What the add / change dialog gives back.
typedef ProfileLook = ({String name, int colour, String icon});

/// Asks for a profile's name, colour and picture. [start] fills it in (changing a profile).
Future<ProfileLook?> showProfileEditor(BuildContext context,
    {required String title, required String action, required ProfileLook start}) {
  return showDialog<ProfileLook>(
    context: context,
    builder: (ctx) => _ProfileEditor(title: title, action: action, start: start),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.title, required this.action, required this.start});
  final String title, action;
  final ProfileLook start;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.start.name);
  late int _colour = widget.start.colour;
  late String _icon = widget.start.icon;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, colour: _colour, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final preview = Profile(id: 'p0', name: _name.text, colour: _colour, icon: _icon);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: ProfileAvatar(preview, size: 72)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _done(),
            ),
            const SizedBox(height: 8),
            Text('Colour', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in ProfilesModel.colours)
                _Pick(
                  selected: c == _colour,
                  onTap: () => setState(() => _colour = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Text('Picture', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final e in profileIcons.entries)
                _Pick(
                  selected: e.key == _icon,
                  onTap: () => setState(() => _icon = e.key),
                  child: SizedBox(width: 32, height: 32, child: Icon(e.value)),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _name.text.trim().isEmpty ? null : _done, child: Text(widget.action)),
      ],
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({required this.selected, required this.onTap, required this.child});
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
        ),
        child: child,
      ),
    );
  }
}

/// Switches to profile [id]: open pages close (everything starts afresh for them), what's
/// playing stops, and their things load. Shows a moment's "Switching…" while it does.
Future<void> switchProfile(BuildContext context, String id) async {
  final profiles = profilesOf(context, listen: false);
  if (profiles == null) return;
  if (id == profiles.currentId) {
    await profiles.switchTo(id); // just marks "Who's listening?" as answered
    return;
  }
  appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  final name = profiles.byId(id)?.name ?? '';
  appNavigatorKey.currentState?.push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    pageBuilder: (context, animation, secondary) => PopScope(
      canPop: false,
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 16),
                Text('Switching to $name…'),
              ]),
            ),
          ),
        ),
      ),
    ),
  ));
  try {
    await profiles.switchTo(id);
  } finally {
    appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  }
}

/// The list of profiles to switch to (the sidebar's and Home's profile button).
Future<void> showProfileSwitcher(BuildContext context) async {
  final profiles = profilesOf(context, listen: false);
  if (profiles == null || !profiles.on) return;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Who\'s listening?'),
      children: [
        for (final p in profiles.profiles)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, p.id),
            child: Row(children: [
              ProfileAvatar(p, size: 36),
              const SizedBox(width: 14),
              Expanded(child: Text(p.name, style: const TextStyle(fontSize: 16))),
              if (p.id == profiles.currentId) Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary),
            ]),
          ),
      ],
    ),
  );
  if (picked == null || !context.mounted) return;
  await switchProfile(context, picked);
}

/// The person's circle, which opens the switcher; nothing when profiles are off. For the
/// sidebar (PC) and Home's top bar (phone).
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    final profiles = profilesOf(context);
    final me = profiles?.on == true ? profiles!.current : null;
    if (me == null) return const SizedBox.shrink();
    return Tooltip(
      message: '${me.name} · Switch profile',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showProfileSwitcher(context),
        child: Padding(padding: const EdgeInsets.all(4), child: ProfileAvatar(me, size: size)),
      ),
    );
  }
}
