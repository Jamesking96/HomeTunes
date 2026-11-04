// "Look up online" beside the Genre box in Edit details and Edit collection (4 Nov 2026): asks
// TVmaze, AniList or iTunes for the collection's genres (VideoLibraryModel.findGenresOnline) and
// puts them in the box ("Comedy, Drama"), to keep or change before saving. Nothing is saved until
// the editor is.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/video_library_model.dart';
import 'offline_warning.dart';

class GenreLookupButton extends StatefulWidget {
  /// The box the genres go in.
  final TextEditingController controller;

  /// The name to look up (the collection's name as typed in the editor now).
  final String Function() name;

  /// The collection's type ("Anime", "TV", "Films"…), which decides the services asked first.
  final String? Function() type;

  /// Its year, when known (picks between remakes).
  final int? Function() year;

  /// Called after the box has been filled.
  final VoidCallback? onFound;

  const GenreLookupButton({
    super.key,
    required this.controller,
    required this.name,
    required this.type,
    required this.year,
    this.onFound,
  });

  @override
  State<GenreLookupButton> createState() => _GenreLookupButtonState();
}

class _GenreLookupButtonState extends State<GenreLookupButton> {
  bool _busy = false;

  Future<void> _lookUp() async {
    final name = widget.name().trim();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (name.isEmpty) {
      messenger?.showSnackBar(const SnackBar(content: Text('Give it a collection name first.')));
      return;
    }
    if (!await ensureOnline(context) || !mounted) return;
    setState(() => _busy = true);
    try {
      final found = await context.read<VideoLibraryModel>().findGenresOnline(name, type: widget.type(), year: widget.year());
      if (!mounted) return;
      if (found.found) {
        widget.controller.text = found.genres.join(', ');
        widget.onFound?.call();
        messenger?.showSnackBar(SnackBar(content: Text('Genres from ${found.source}. Save to keep them.')));
      } else {
        messenger?.showSnackBar(SnackBar(
            content: Text(found.incomplete
                ? 'Couldn\'t reach the genre services. Try again in a while.'
                : 'No genres found for "$name". You can type them in.')));
      }
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(content: Text('Couldn\'t look up genres just now.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('genre-lookup'),
      tooltip: 'Look up genres online',
      onPressed: _busy ? null : _lookUp,
      icon: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.travel_explore),
    );
  }
}
