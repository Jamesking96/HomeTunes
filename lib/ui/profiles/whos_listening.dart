// "Who's listening?" (Profiles, phase 1): with profiles on, HomeTunes asks at every start (the
// user, 8 Nov: "It should ask"). The last profile used is already loaded behind it, so picking
// that one is instant; another one switches (profile_ui.dart switchProfile).
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tv/tv_focus.dart' show tvModeOf;
import '../tv/tv_widgets.dart' show TvFocusFrame, TvPressable;
import 'profile_ui.dart';

/// Shows [child] (the app), or "Who's listening?" first when profiles are on and nobody has been
/// picked since HomeTunes opened.
class WhosListeningGate extends StatelessWidget {
  const WhosListeningGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final profiles = profilesOf(context);
    if (profiles == null || !profiles.needsChoosing) return child;
    return const WhosListeningScreen();
  }
}

/// Big cards, one per profile; the last one used has the focus (the remote's OK picks it).
class WhosListeningScreen extends StatelessWidget {
  const WhosListeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profiles = profilesOf(context)!;
    final size = MediaQuery.sizeOf(context);
    final card = (size.shortestSide / 4).clamp(96.0, 180.0);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Who\'s listening?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final p in profiles.profiles)
                    _ProfileCard(
                      key: ValueKey('whos:${p.id}'),
                      size: card,
                      autofocus: p.id == profiles.currentId,
                      onPick: () => switchProfile(context, p.id),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ProfileAvatar(p, size: card),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: card + 16,
                          child: Text(p.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16)),
                        ),
                      ]),
                    ),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(
      {super.key, required this.size, required this.autofocus, required this.onPick, required this.child});
  final double size;
  final bool autofocus;
  final VoidCallback onPick;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // On the TV (phase 2): the remote's focus ring, and the card grows a little, as elsewhere.
    if (tvModeOf(context)) {
      return TvPressable(
        autofocus: autofocus,
        onPressed: onPick,
        builder: (context, focused) => TvFocusFrame(
          focused: focused,
          radius: 20,
          child: Container(
            padding: const EdgeInsets.all(10),
            color: focused ? AppColors.surfaceHigh : Colors.transparent,
            child: child,
          ),
        ),
      );
    }
    return InkWell(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(16),
      onTap: onPick,
      child: Padding(padding: const EdgeInsets.all(8), child: child),
    );
  }
}
