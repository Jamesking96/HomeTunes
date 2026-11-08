// Settings › Profiles (phase 1; plan: claude/06_PROFILES_PLAN.md). Off by default. Turning it on
// makes the first profile from everything there is now (nothing is lost or reset); then each
// person has their own places, playlists, edits, look and settings, and HomeTunes asks
// "Who's listening?" at every start. The folders, the servers and the downloads stay shared.
import 'package:flutter/material.dart';

import '../../../state/profiles_model.dart';
import '../../profiles/profile_ui.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

class ProfileSettings extends StatefulWidget {
  const ProfileSettings({super.key});

  @override
  State<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends State<ProfileSettings> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('That didn\'t work: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOn(ProfilesModel m) async {
    final kept = m.byId(m.last);
    if (kept != null) {
      // Turned on before: the things in use now go back to the profile they came from.
      await _run(() => m.turnOn());
      return;
    }
    final look = await showProfileEditor(context,
        title: 'Your profile',
        action: 'Turn on profiles',
        start: (name: '', colour: m.nextColour(), icon: 'person'));
    if (look == null || !mounted) return;
    await _run(() => m.turnOn(name: look.name, colour: look.colour, icon: look.icon));
  }

  Future<void> _turnOff(ProfilesModel m) async {
    String? keep = m.currentId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Turn off profiles?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Whose things should everyone use from now on? The other profiles are kept, '
                'and come back if you turn profiles on again.'),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: keep,
              onChanged: (v) => setInner(() => keep = v),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final p in m.profiles)
                  RadioListTile<String>(
                    value: p.id,
                    title: Text(p.name),
                    secondary: ProfileAvatar(p, size: 32),
                  ),
              ]),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
          ],
        ),
      ),
    );
    if (ok != true || keep == null || !mounted) return;
    await _run(() => m.turnOff(keep!));
  }

  Future<void> _add(ProfilesModel m) async {
    final look = await showProfileEditor(context,
        title: 'Add a profile', action: 'Add', start: (name: '', colour: m.nextColour(), icon: 'person'));
    if (look == null || !mounted) return;
    await _run(() => m.add(name: look.name, colour: look.colour, icon: look.icon));
  }

  Future<void> _change(ProfilesModel m, Profile p) async {
    final look = await showProfileEditor(context,
        title: 'Change ${p.name}', action: 'Save', start: (name: p.name, colour: p.colour, icon: p.icon));
    if (look == null || !mounted) return;
    await _run(() => m.update(p.id, name: look.name, colour: look.colour, icon: look.icon));
  }

  Future<void> _remove(ProfilesModel m, Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${p.name}?'),
        content: Text('Everything that was ${p.name}\'s goes: their places in books and videos, playlists, '
            'Liked Songs, edits and settings. The music, books and videos themselves stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => m.remove(p.id));
  }

  @override
  Widget build(BuildContext context) {
    final m = profilesOf(context);
    if (m == null) {
      return const SettingsPageList(children: [SettingsGroupTitle('Profiles', 'Not available here.')]);
    }
    return SettingsPageList(children: [
      const SettingsGroupTitle(
        'Profiles',
        'Share HomeTunes with the people you live with. Each person has their own places in books and '
            'videos, playlists and Liked Songs, edits, look and settings. The folders, servers and downloads '
            'stay shared.',
      ),
      SettingTarget('profiles-on', child: SwitchListTile(
        title: const Text('Use profiles'),
        subtitle: Text(m.on
            ? 'HomeTunes asks who\'s listening each time it opens'
            : 'Off: everyone shares the same things, as now'),
        value: m.on,
        onChanged: _busy ? null : (v) => v ? _turnOn(m) : _turnOff(m),
      )),
      if (_busy) const LinearProgressIndicator(),
      if (m.on) ...[
        SettingTarget('profiles-list', child: Column(children: [
          for (final p in m.profiles)
            ListTile(
              key: ValueKey('profile-row:${p.id}'),
              leading: ProfileAvatar(p),
              title: Text(p.name),
              subtitle: p.id == m.currentId ? const Text('Using now') : null,
              onTap: _busy || p.id == m.currentId ? null : () => switchProfile(context, p.id),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Change name, colour or picture',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _busy ? null : () => _change(m, p),
                ),
                if (p.id != m.currentId)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : () => _remove(m, p),
                  ),
              ]),
            ),
        ])),
        SettingTarget('profiles-add', child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.add)),
          title: const Text('Add a profile'),
          subtitle: Text('Starts with a copy of ${m.current?.name ?? 'your'}\'s edits; everything else starts fresh',
              style: TextStyle(color: AppColors.textDim)),
          onTap: _busy ? null : () => _add(m),
        )),
      ],
    ]);
  }
}
