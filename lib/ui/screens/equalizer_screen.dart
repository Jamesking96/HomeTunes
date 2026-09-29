// The Equaliser screen: pick a preset (heard straight away), edit its ten
// bands and overall level, put a built-in preset back as it came, and make,
// rename or delete your own. Music and audiobooks can each have their own preset.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/eq_preset.dart';
import '../../state/equalizer_model.dart';
import '../theme.dart';
import '../widgets/track_tile.dart' show askForName;

/// Opens the Equaliser, showing the audiobook preset if [forBooks] (e.g. from Now Playing during a book).
Future<void> openEqualizer(BuildContext context, {bool? forBooks}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => EqualizerScreen(forBooks: forBooks)));

class EqualizerScreen extends StatefulWidget {
  final bool? forBooks;
  const EqualizerScreen({super.key, this.forBooks});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  late bool _books;
  bool _editing = false;
  late final EqualizerModel _eq;

  @override
  void initState() {
    super.initState();
    final eq = _eq = context.read<EqualizerModel>();
    _books = eq.separateBooks && (widget.forBooks ?? false);
  }

  @override
  void dispose() {
    _eq.flush(); // save a slider change that's still waiting
    super.dispose();
  }

  Future<void> _newPreset(EqualizerModel eq, EqPreset from) async {
    final name = await askForName(context, title: 'Name your preset');
    if (name == null || name.trim().isEmpty) return;
    final id = await eq.addCustom(name, from: from);
    await eq.choose(id, forBooks: _books);
    if (mounted) setState(() => _editing = true);
  }

  Future<void> _rename(EqualizerModel eq, EqPreset p) async {
    final name = await askForName(context, title: 'Rename preset', initial: p.name);
    if (name != null) await eq.rename(p.id, name);
  }

  Future<void> _delete(EqualizerModel eq, EqPreset p) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('Anything using it goes back to a built-in preset.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (sure == true) {
      await eq.delete(p.id);
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerModel>();
    final unavailable = eq.unavailable;
    if (!eq.separateBooks) _books = false;
    final current = eq.presetFor(book: _books);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equaliser'),
        actions: [
          Text(eq.enabled ? 'On' : 'Off', style: TextStyle(color: AppColors.textDim)),
          Switch(key: const ValueKey('eq-on'), value: eq.enabled, onChanged: eq.setEnabled),
          PopupMenuButton<void>(
            tooltip: 'More',
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: eq.presets.any((p) => eq.isEdited(p.id)),
                onTap: eq.restoreAll,
                child: const Text('Restore all presets'),
              ),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            if (unavailable)
              const _Notice(
                icon: Icons.error_outline,
                text: 'The equaliser isn\'t available on this device, so these settings aren\'t heard.',
              )
            else if (!eq.enabled)
              const _Notice(
                icon: Icons.info_outline,
                text: 'The equaliser is off. Pick a preset, or switch it on at the top, to hear it.',
              ),
            if (eq.separateBooks) ...[
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.music_note_outlined), label: Text('Music')),
                  ButtonSegment(value: true, icon: Icon(Icons.menu_book_outlined), label: Text('Audiobooks')),
                ],
                selected: {_books},
                onSelectionChanged: (v) => setState(() {
                  _books = v.first;
                  _editing = false;
                }),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in eq.presets)
                ChoiceChip(
                  key: ValueKey('eq-preset-${p.id}'),
                  avatar: p.builtIn ? null : const Icon(Icons.tune, size: 16),
                  label: Text(eq.isEdited(p.id) ? '${p.name} · edited' : p.name),
                  selected: p.id == current.id,
                  onSelected: (_) {
                    eq.choose(p.id, forBooks: _books);
                    setState(() => _editing = false);
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: () => _newPreset(eq, current),
              ),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppShape.circular(12)),
              child: _editing
                  ? _BandSliders(preset: current, onChanged: (g) => eq.adjust(current.id, gains: g))
                  : _Curve(preset: current, color: eq.enabled ? accent : AppColors.textDim),
            ),
            if (_editing) ...[
              const SizedBox(height: 12),
              Text('Overall level: ${_db(current.level)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              Slider(
                key: const ValueKey('eq-level'),
                value: current.level,
                min: eqMinLevel,
                max: 0,
                divisions: 24,
                label: _db(current.level),
                onChanged: (v) => eq.adjust(current.id, level: v),
              ),
              Text(
                'Turn this down when you boost bands, so loud music doesn\'t distort.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  current.level == 0 ? 'Overall level unchanged' : 'Overall level ${_db(current.level)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton.icon(
                key: const ValueKey('eq-edit'),
                icon: Icon(_editing ? Icons.check : Icons.tune),
                label: Text(_editing ? 'Done' : 'Edit'),
                onPressed: () {
                  if (!_editing && !eq.enabled) eq.setEnabled(true);
                  setState(() => _editing = !_editing);
                },
              ),
              if (current.builtIn && eq.isEdited(current.id))
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore default'),
                  onPressed: () => eq.restoreDefault(current.id),
                ),
              if (!current.builtIn) ...[
                OutlinedButton(onPressed: () => _rename(eq, current), child: const Text('Rename')),
                TextButton(onPressed: () => _delete(eq, current), child: const Text('Delete')),
              ],
            ]),
            const SizedBox(height: 24),
            Text(
              eq.separateBooks
                  ? 'Audiobooks switch to their own preset when a book starts, and music switches back. '
                      'You can turn that off in Settings › Audiobooks.'
                  : 'Music and audiobooks use the same preset. Settings › Audiobooks can give books their own.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }

  static String _db(double v) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return v > 0 ? '+$s dB' : (v < 0 ? '−${s.substring(1)} dB' : '0 dB');
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Notice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppShape.circular(8)),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13))),
        ]),
      );
}

/// A small picture of a preset: a bar per band, up for boost and down for cut.
class _Curve extends StatelessWidget {
  final EqPreset preset;
  final Color color;
  const _Curve({required this.preset, required this.color});

  @override
  Widget build(BuildContext context) {
    const half = 56.0;
    return Column(children: [
      SizedBox(
        height: half * 2,
        child: Stack(children: [
          Center(child: Divider(height: 1, color: AppColors.surfaceHigh)),
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final g in preset.gains)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(height: g > 0 ? half * g / eqMaxGain : 0, color: color),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(height: g < 0 ? half * -g / eqMaxGain : 0, color: color.withValues(alpha: 0.6)),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 6),
      const _BandLabels(),
    ]);
  }
}

class _BandLabels extends StatelessWidget {
  const _BandLabels();

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final hz in eqBands)
          Expanded(
            child: Text(eqBandLabel(hz),
                textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.textDim)),
          ),
      ]);
}

/// Ten upright sliders, one per band, −12 to +12 dB. Changes are heard while dragging.
class _BandSliders extends StatelessWidget {
  final EqPreset preset;
  final ValueChanged<List<double>> onChanged;
  const _BandSliders({required this.preset, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 200,
        child: Row(children: [
          for (var i = 0; i < eqBands.length; i++)
            Expanded(
              child: Column(children: [
                Text(_short(preset.gains[i]), style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Theme.of(context).colorScheme.primary,
                        thumbColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: Slider(
                        key: ValueKey('eq-band-$i'),
                        value: preset.gains[i],
                        min: -eqMaxGain,
                        max: eqMaxGain,
                        divisions: 48,
                        onChanged: (v) {
                          final g = List.of(preset.gains);
                          g[i] = v;
                          onChanged(g);
                        },
                      ),
                    ),
                  ),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      const _BandLabels(),
    ]);
  }

  static String _short(double g) {
    final s = g == g.roundToDouble() ? g.toStringAsFixed(0) : g.toStringAsFixed(1);
    return g > 0 ? '+$s' : s;
  }
}
