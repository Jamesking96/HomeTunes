// Settings › Profiles (phase 1; plan: claude/06_PROFILES_PLAN.md). Off by default. Turning it on
// makes the first profile from everything there is now (nothing is lost or reset); then each
// person has their own places, playlists, edits, look and settings, and HomeTunes asks
// "Who's listening?" at every start. The folders, the servers and the downloads stay shared.
import 'package:flutter/material.dart';

import '../../../state/profiles_model.dart';
import '../../profiles/profile_pin.dart';
import '../../profiles/profile_ui.dart';
import '../../theme.dart';
import '../../tv/tv_focus.dart' show tvModeOf;
import '../../tv/tv_options.dart';
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
        start: profileLook('', m.nextColour(), 'person'));
    if (look == null || !mounted) return;
    await _run(() async {
      await m.turnOn(name: look.name, colour: look.colour, icon: look.icon);
      final id = m.currentId;
      if (id != null && look.newPhoto != null) await m.setPhoto(id, look.newPhoto);
    });
  }

  Future<void> _turnOff(ProfilesModel m) async {
    if (tvModeOf(context)) {
      // The TV's options panel (phase 2): whose things to keep, on the one in use.
      String? kept;
      await showTvOptions(
        context,
        title: 'Turn off profiles',
        subtitle: 'Whose things should everyone use? The others are kept.',
        focusIndex: m.profiles.indexWhere((p) => p.id == m.currentId).clamp(0, m.profiles.length - 1),
        options: [
          for (final p in m.profiles)
            TvOption('Keep ${p.name}\'s', Icons.person, () => kept = p.id, picture: ProfileAvatar(p, size: 36)),
        ],
      );
      if (kept == null || !mounted) return;
      if (!await _pinToKeep(m, kept!)) return;
      await _run(() => m.turnOff(kept!));
      return;
    }
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
    if (!await _pinToKeep(m, keep!)) return;
    await _run(() => m.turnOff(keep!));
  }

  /// Keeping someone else's things means switching into them: their PIN is asked (phase 5).
  Future<bool> _pinToKeep(ProfilesModel m, String id) async {
    final p = m.byId(id);
    if (p == null || id == m.currentId || !p.hasPin) return true;
    return askProfilePin(context, p);
  }

  /// Settings › Profiles › PIN (phase 5): only for the profile in use (decision 4: set up inside
  /// the profile). Changing or removing one asks for the current PIN first.
  Future<void> _pin(ProfilesModel m) async {
    final me = m.current;
    if (me == null) return;
    String? action = me.hasPin ? null : 'set';
    if (me.hasPin) {
      if (tvModeOf(context)) {
        await showTvOptions(context, title: 'PIN for ${me.name}', options: [
          TvOption('Change the PIN', Icons.password, () => action = 'set', opensMore: true),
          TvOption('Remove the PIN', Icons.lock_open, () => action = 'remove'),
        ]);
      } else {
        action = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(title: Text('PIN for ${me.name}'), children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'set'), child: const Text('Change the PIN')),
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove the PIN')),
          ]),
        );
      }
      if (action == null || !mounted) return;
      if (!await askProfilePin(context, me) || !mounted) return;
    }
    if (action == 'remove') {
      await _run(() => m.setPin(null));
      return;
    }
    final pin = await choosePin(context, me.name);
    if (pin == null || !mounted) return;
    await _run(() => m.setPin(pin));
  }

  Future<void> _add(ProfilesModel m) async {
    final look = await showProfileEditor(context,
        title: 'Add a profile', action: 'Add', start: profileLook('', m.nextColour(), 'person'));
    if (look == null || !mounted) return;
    await _run(() async {
      final added = await m.add(name: look.name, colour: look.colour, icon: look.icon);
      if (look.newPhoto != null) await m.setPhoto(added.id, look.newPhoto);
    });
  }

  Future<void> _change(ProfilesModel m, Profile p) async {
    final look = await showProfileEditor(context,
        title: 'Change ${p.name}',
        action: 'Save',
        start: profileLook(p.name, p.colour, p.icon),
        photoFile: m.photoFile(p));
    if (look == null || !mounted) return;
    await _run(() => applyProfileLook(m, p.id, look));
  }

  Future<void> _remove(ProfilesModel m, Profile p) async {
    if (tvModeOf(context)) {
      var yes = false;
      await showTvOptions(
        context,
        title: 'Remove ${p.name}?',
        subtitle: 'Their places, playlists, edits and settings go',
        picture: ProfileAvatar(p, size: 64),
        focusIndex: 1,
        options: [
          TvOption('Remove ${p.name}', Icons.delete_outline, () => yes = true),
          TvOption('Keep ${p.name}', Icons.close, () {}),
        ],
      );
      if (yes && mounted) await _run(() => m.remove(p.id));
      return;
    }
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
            ? 'Everyone keeps their own things'
            : 'Off: everyone shares the same things, as now'),
        value: m.on,
        onChanged: _busy ? null : (v) => v ? _turnOn(m) : _turnOff(m),
      )),
      if (_busy) const LinearProgressIndicator(),
      if (m.on)
        // 8 Nov: open straight into the last one used (on at first), or ask each time.
        SwitchListTile(
          key: const ValueKey('profiles-open-last'),
          title: const Text('Open with the last profile used'),
          subtitle: Text(m.openLast
              ? 'HomeTunes opens as ${m.byId(m.last)?.name ?? 'the last one used'}; switch any time from '
                  '${tvModeOf(context) ? 'the menu' : 'your picture'}'
              : 'Off: HomeTunes asks who\'s listening each time it opens'),
          value: m.openLast,
          onChanged: _busy ? null : (v) => m.setOpenLast(v),
        ),
      if (m.on) ...[
        SettingTarget('profiles-list', child: Column(children: [
          for (final p in m.profiles)
            ListTile(
              key: ValueKey('profile-row:${p.id}'),
              leading: ProfileAvatar(p),
              title: Text(p.name),
              subtitle: p.id == m.currentId || p.hasPin
                  ? Text([if (p.id == m.currentId) 'Using now', if (p.hasPin) 'PIN set'].join(' · '))
                  : null,
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
        // Phase 5: an optional PIN for the profile in use.
        if (m.current case final me?)
          ListTile(
            key: const ValueKey('profiles-pin'),
            leading: Icon(me.hasPin ? Icons.lock_outline : Icons.lock_open_outlined),
            title: Text(me.hasPin ? 'PIN for ${me.name}: on' : 'PIN for ${me.name}'),
            subtitle: Text(
                me.hasPin
                    ? 'Asked when someone switches to ${me.name}. Change or remove it'
                    : 'Off: anyone can switch to ${me.name}. Set a PIN so it\'s asked for',
                style: TextStyle(color: AppColors.textDim)),
            onTap: _busy ? null : () => _pin(m),
          ),
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
