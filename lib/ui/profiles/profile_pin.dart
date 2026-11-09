// Profile PINs (Profiles, phase 5; the user's decision 4: "A PIN is optional, set up inside a
// profile; trusted by default. It protects switching into that profile (at start or from
// Switch); once in, everything works as normal").
//
// askProfilePin: "Enter Sam's PIN" (a dialog with a number box, or the TV keyboard's number pad),
// checked by ProfilesModel.checkPin; five wrong tries in a row wait 30 seconds.
// choosePin: a new PIN typed twice (Settings › Profiles › PIN).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/profiles_model.dart';
import '../tv/tv_focus.dart' show tvModeOf;
import '../tv/tv_keyboard.dart' show showTvTextInput;
import '../tv/tv_words.dart' show TvTyping;
import 'profile_ui.dart' show profilesOf, ProfileAvatar;

const _forgot = 'Forgot it? Someone using another profile can remove this one in Settings › Profiles '
    '(its places, playlists and settings go with it).';

String _waitText(Duration d) => 'Too many wrong tries. Try again in ${d.inSeconds.clamp(1, 999)} seconds.';

/// Asks for [p]'s PIN until it's right (true) or the person gives up (false).
Future<bool> askProfilePin(BuildContext context, Profile p) async {
  final profiles = profilesOf(context, listen: false);
  if (profiles == null || !p.hasPin) return true;
  if (tvModeOf(context)) {
    String? note;
    while (context.mounted) {
      final wait = profiles.pinWaitLeft(p.id);
      final typed = await showTvTextInput(
        context,
        title: 'Enter ${p.name}\'s PIN',
        hint: wait > Duration.zero ? _waitText(wait) : (note ?? 'The numbers ${p.name} chose'),
        obscure: true,
        maxLength: 8,
        typing: TvTyping.number,
      );
      if (typed == null) return false;
      switch (profiles.checkPin(p.id, typed)) {
        case PinCheck.right:
          return true;
        case PinCheck.wrong:
          note = 'That\'s not the PIN. Try again.';
        case PinCheck.wait:
          note = null;
      }
    }
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _PinDialog(profile: p, profiles: profiles),
  );
  return ok == true;
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({required this.profile, required this.profiles});
  final Profile profile;
  final ProfilesModel profiles;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _box = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _box.dispose();
    super.dispose();
  }

  void _check() {
    final p = widget.profile;
    switch (widget.profiles.checkPin(p.id, _box.text)) {
      case PinCheck.right:
        Navigator.pop(context, true);
      case PinCheck.wrong:
        setState(() => _error = 'That\'s not the PIN. Try again.');
      case PinCheck.wait:
        setState(() => _error = _waitText(widget.profiles.pinWaitLeft(p.id)));
    }
    _box.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return AlertDialog(
      title: Row(children: [
        ProfileAvatar(p, size: 36),
        const SizedBox(width: 12),
        Expanded(child: Text('Enter ${p.name}\'s PIN')),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          key: const ValueKey('profile-pin-box'),
          controller: _box,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          decoration: InputDecoration(labelText: 'PIN', errorText: _error),
          onSubmitted: (_) => _check(),
        ),
        const SizedBox(height: 12),
        Text(_forgot, style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _check, child: const Text('OK')),
      ],
    );
  }
}

/// Asks for a new PIN twice. Returns it, or null if the person gave up.
Future<String?> choosePin(BuildContext context, String name) async {
  if (tvModeOf(context)) {
    String? note;
    while (true) {
      if (!context.mounted) return null;
      final first = await showTvTextInput(context,
          title: 'Choose a PIN for $name', hint: note ?? '4 to 8 numbers', obscure: true, maxLength: 8, typing: TvTyping.number);
      if (first == null) return null;
      if (!ProfilesModel.pinPattern.hasMatch(first)) {
        note = 'A PIN is 4 to 8 numbers.';
        continue;
      }
      if (!context.mounted) return null;
      final again = await showTvTextInput(context,
          title: 'Type the PIN again', hint: 'To make sure', obscure: true, maxLength: 8, typing: TvTyping.number);
      if (again == null) return null;
      if (again == first) return first;
      note = 'The two didn\'t match. Try again.';
    }
  }
  return showDialog<String>(context: context, builder: (_) => _NewPinDialog(name: name));
}

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({required this.name});
  final String name;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _first = TextEditingController(), _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _again.dispose();
    super.dispose();
  }

  void _save() {
    if (!ProfilesModel.pinPattern.hasMatch(_first.text)) {
      setState(() => _error = 'A PIN is 4 to 8 numbers.');
    } else if (_first.text != _again.text) {
      setState(() => _error = 'The two didn\'t match.');
    } else {
      Navigator.pop(context, _first.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration box(String label, [String? error]) => InputDecoration(labelText: label, errorText: error);
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)];
    return AlertDialog(
      title: Text('Choose a PIN for ${widget.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Anyone switching to this profile will be asked for it. Once in, everything works as usual.'),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('new-pin-1'),
          controller: _first,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: box('PIN (4 to 8 numbers)'),
        ),
        TextField(
          key: const ValueKey('new-pin-2'),
          controller: _again,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: box('Type it again', _error),
          onSubmitted: (_) => _save(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save PIN')),
      ],
    );
  }
}
