// Pieces of Profiles (phase 1) used on several screens: a profile's circle, the list of pictures
// and colours to choose from, the add / change dialog, the switcher and switching itself.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/profiles_model.dart';
import '../screens/settings/update_ui.dart' show appNavigatorKey;
import '../screens/video_pictures.dart' show preparePicture, showPictureSearch;
import '../theme.dart';
import '../tv/tv_focus.dart' show tvModeOf;
import '../tv/tv_keyboard.dart' show showTvTextInput;
import '../tv/tv_menus.dart' show tvNotice;
import '../tv/tv_options.dart';
import '../tv/tv_pictures.dart' show showTvPictureSearch;

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
  const ProfileAvatar(this.profile, {super.key, this.size = 40, this.image});
  final Profile profile;
  final double size;

  /// A picture to show instead of the profile's own (the editor's preview of a new one).
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final colour = Color(profile.colour);
    final dark = ThemeData.estimateBrightnessForColor(colour) == Brightness.dark;
    // Their own picture, when they have one (8 Nov).
    final file = image == null ? profilesOf(context, listen: false)?.photoFile(profile) : null;
    final picture = image ?? (file == null ? null : FileImage(File(file)));
    if (picture != null) {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image(
          image: ResizeImage.resizeIfNeeded(px * 2, null, picture),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(profileIcon(profile.icon), size: size * 0.55),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(profileIcon(profile.icon), size: size * 0.55, color: dark ? Colors.white : Colors.black87),
    );
  }
}

/// What the add / change dialog gives back. [newPhoto]: a picture chosen now (from the device or
/// found online, already made a sensible size); [removePhoto]: back to the colour and icon.
typedef ProfileLook = ({String name, int colour, String icon, List<int>? newPhoto, bool removePhoto});

/// A look to start the editor with (no photo change).
ProfileLook profileLook(String name, int colour, String icon) =>
    (name: name, colour: colour, icon: icon, newPhoto: null, removePhoto: false);

/// Saves [look] for [id] (name, colour, icon, and the photo when it changed).
Future<void> applyProfileLook(ProfilesModel m, String id, ProfileLook look) async {
  await m.update(id, name: look.name, colour: look.colour, icon: look.icon);
  if (look.newPhoto != null) {
    await m.setPhoto(id, look.newPhoto);
  } else if (look.removePhoto) {
    await m.setPhoto(id, null);
  }
}

/// A picture from a file on this device, made a sensible size; null if none was picked.
Future<List<int>?> pickProfilePhoto() async {
  final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture');
  final path = file?.path;
  if (path == null) return null;
  return preparePicture(await File(path).readAsBytes());
}

/// The colours' names, for the TV's list (same order as [ProfilesModel.colours]).
const profileColourNames = ['Coral', 'Sky blue', 'Green', 'Purple', 'Yellow', 'Pink', 'Teal', 'Grey'];

/// The pictures' names, for the TV's list.
const profileIconNames = <String, String>{
  'person': 'Person',
  'headphones': 'Headphones',
  'music': 'Music note',
  'book': 'Book',
  'movie': 'Film',
  'star': 'Star',
  'heart': 'Heart',
  'pets': 'Paw',
  'rocket': 'Rocket',
  'game': 'Game controller',
  'flower': 'Flower',
  'sun': 'Sun',
};

/// Asks for a profile's name, colour and picture. [start] fills it in (changing a profile), with
/// [photoFile] its own picture if it has one. A picture can come from this device or be found
/// online (8 Nov). On the TV (phase 2) it's steps with the remote: the name on the TV keyboard,
/// then the picture, colour and icon from the options panel.
Future<ProfileLook?> showProfileEditor(BuildContext context,
    {required String title, required String action, required ProfileLook start, String? photoFile}) {
  if (tvModeOf(context)) return _tvProfileEditor(context, title: title, start: start, photoFile: photoFile);
  return showDialog<ProfileLook>(
    context: context,
    builder: (ctx) => _ProfileEditor(title: title, action: action, start: start, photoFile: photoFile),
  );
}

Future<ProfileLook?> _tvProfileEditor(BuildContext context,
    {required String title, required ProfileLook start, String? photoFile}) async {
  final typed = await showTvTextInput(context, title: '$title: name', initial: start.name, maxLength: 30);
  final name = typed?.trim() ?? '';
  if (name.isEmpty || !context.mounted) return null;
  // Their own picture, or a colour and icon.
  String? how;
  await showTvOptions(
    context,
    title: 'A picture for $name',
    options: [
      if (photoFile != null) TvOption('Keep this picture', Icons.check, () => how = 'keep'),
      TvOption('Search online', Icons.travel_explore, opensMore: true,
          subtitle: 'Characters, shows and more from AniList, TVmaze and Wikipedia', () => how = 'online'),
      TvOption('Choose a picture file', Icons.folder_open, opensMore: true,
          subtitle: 'A picture on this TV or a USB drive', () => how = 'file'),
      TvOption('A colour and an icon', Icons.palette_outlined, opensMore: true, () => how = 'icon'),
    ],
  );
  if (how == null || !context.mounted) return null;
  if (how != 'icon') {
    List<int>? photo;
    try {
      photo = how == 'keep'
          ? null
          : how == 'online'
              ? await showTvPictureSearch(context, query: name)
              : await pickProfilePhoto();
    } catch (e) {
      if (context.mounted) tvNotice(context, 'Couldn\'t use that picture: ${e is FormatException ? e.message : e}');
      return null;
    }
    if (how != 'keep' && photo == null) return null;
    return (name: name, colour: start.colour, icon: start.icon, newPhoto: photo, removePhoto: false);
  }
  int? colour;
  await showTvOptions(
    context,
    title: 'A colour for $name',
    focusIndex: ProfilesModel.colours.indexOf(start.colour).clamp(0, ProfilesModel.colours.length - 1),
    options: [
      for (var i = 0; i < ProfilesModel.colours.length; i++)
        TvOption(profileColourNames[i], Icons.circle, () => colour = ProfilesModel.colours[i],
            picture: ColoredBox(color: Color(ProfilesModel.colours[i]))),
    ],
  );
  if (colour == null || !context.mounted) return null;
  String? icon;
  final icons = profileIcons.keys.toList();
  await showTvOptions(
    context,
    title: 'An icon for $name',
    focusIndex: icons.indexOf(start.icon).clamp(0, icons.length - 1),
    options: [
      for (final k in icons)
        TvOption(profileIconNames[k] ?? k, profileIcons[k]!, () => icon = k,
            picture: ProfileAvatar(Profile(id: 'p0', name: name, colour: colour!, icon: k), size: 36)),
    ],
  );
  if (icon == null) return null;
  return (name: name, colour: colour!, icon: icon!, newPhoto: null, removePhoto: photoFile != null);
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({required this.title, required this.action, required this.start, this.photoFile});
  final String title, action;
  final ProfileLook start;
  final String? photoFile;

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.start.name);
  late int _colour = widget.start.colour;
  late String _icon = widget.start.icon;

  /// A picture chosen now, and whether the one they had is being taken away.
  List<int>? _photo;
  bool _removed = false;
  bool _getting = false;

  bool get _hasPhoto => _photo != null || (widget.photoFile != null && !_removed);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context,
        (name: name, colour: _colour, icon: _icon, newPhoto: _photo, removePhoto: _removed && _photo == null));
  }

  Future<void> _getPhoto(Future<List<int>?> Function() get) async {
    setState(() => _getting = true);
    try {
      final bytes = await get();
      if (bytes != null && mounted) setState(() => _photo = bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: ${e is FormatException ? e.message : e}')));
      }
    } finally {
      if (mounted) setState(() => _getting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = Profile(id: 'p0', name: _name.text, colour: _colour, icon: _icon);
    final ImageProvider? image = _photo != null
        ? MemoryImage(Uint8List.fromList(_photo!))
        : (widget.photoFile != null && !_removed ? FileImage(File(widget.photoFile!)) : null);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: ProfileAvatar(preview, size: 72, image: image)),
            const SizedBox(height: 10),
            // Their own picture (8 Nov): from this device or found online.
            Center(
              child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  key: const ValueKey('profile-photo-file'),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Picture from this device…'),
                  onPressed: _getting ? null : () => _getPhoto(pickProfilePhoto),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('profile-photo-online'),
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: const Text('Search online…'),
                  onPressed: _getting
                      ? null
                      : () => _getPhoto(() => showPictureSearch(context, query: _name.text.trim())),
                ),
                if (_hasPhoto)
                  TextButton(
                    key: const ValueKey('profile-photo-remove'),
                    onPressed: () => setState(() {
                      _photo = null;
                      _removed = true;
                    }),
                    child: const Text('Use a colour and icon'),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
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
  if (tvModeOf(context)) {
    // The TV's options panel, on the one in use (phase 2).
    String? chosen;
    await showTvOptions(
      context,
      title: 'Who\'s listening?',
      subtitle: 'Switch profile',
      focusIndex: profiles.profiles.indexWhere((p) => p.id == profiles.currentId).clamp(0, profiles.profiles.length - 1),
      options: [
        for (final p in profiles.profiles)
          TvOption(p.name, Icons.person, () => chosen = p.id,
              picture: ProfileAvatar(p, size: 36), subtitle: p.id == profiles.currentId ? 'Using now' : null),
      ],
    );
    if (chosen != null && context.mounted) await switchProfile(context, chosen!);
    return;
  }
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
