// Change poster / Change picture on the TV (0.2.5, the user, 29 Oct: "add the option to change
// poster on a media … to the TV build"). On the PC and phone these live in the collection's and the
// video's menus (screens/video_pictures.dart); the TV gets them in its Hold-OK options:
//   - Search online: TVmaze, AniList and Wikipedia (services/video_art_search.dart), shown on a
//     full-screen page of big tiles the remote can move through ([TvPictureSearchPage]); the
//     PC's search window is bigger than the TV's screen;
//   - Choose a picture file: the system's file chooser (on the TV, whatever file manager is set
//     up, as Import backup uses);
//   - Use the automatic poster / picture, once one has been chosen.
// "Pick a frame" isn't offered on the TV: it only works on video files stored on the device (most
// of the TV's videos stream from the server), and its window doesn't fit the TV's screen.
// A chosen picture wins over the server's own poster too (VideoLibraryModel.coverFile).
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../services/video_art_search.dart';
import '../../state/settings/settings_groups.dart' as prefs;
import '../../state/video_library_model.dart';
import '../screens/video_pictures.dart' show pictureSearchHints, preparePicture;
import '../theme.dart';
import '../widgets/offline_warning.dart' show ensureOnline;
import 'tv_browse.dart';
import 'tv_keyboard.dart' show showTvTextInput;
import 'tv_menus.dart' show tvNotice;
import 'tv_options.dart';
import 'tv_widgets.dart';

/// "Change poster" for collection [c], for its Hold-OK options.
TvOption tvChangePosterOption(BuildContext context, VideoCollection c) =>
    TvOption('Change poster', Icons.image_outlined, opensMore: true, () => _choose(context, collection: c));

/// "Change picture" for video [v], for its Hold-OK options.
TvOption tvChangePictureOption(BuildContext context, VideoItem v) =>
    TvOption('Change picture', Icons.image_outlined, opensMore: true, () => _choose(context, video: v));

Future<void> _choose(BuildContext context, {VideoCollection? collection, VideoItem? video}) async {
  final model = context.read<VideoLibraryModel>();
  final online = context.read<prefs.OnlineSettings>().onlineVideoArt;
  final poster = collection != null;
  final name = poster ? collection.name : video!.title;
  final own = poster ? model.hasOwnPoster(collection) : model.hasOwnPicture(video!);
  // Where the new picture goes once it's chosen. A collection is found again by one of its
  // videos, in case it was renamed meanwhile (as the PC's version does).
  final anchor = poster ? (collection.main.isNotEmpty ? collection.main.first : collection.videos.firstOrNull) : video;
  Future<void> save(List<int>? bytes) async {
    if (poster) {
      final now = anchor == null ? collection : (model.collectionOf(model.byId(anchor.id) ?? anchor) ?? collection);
      await model.setPoster(now, bytes);
    } else {
      await model.setPicture(model.byId(video!.id) ?? video, bytes);
    }
  }

  Future<void> use(Future<List<int>?> Function() get) async {
    List<int>? bytes;
    try {
      bytes = await get();
    } catch (e) {
      if (context.mounted) tvNotice(context, 'Couldn\'t use that picture: ${e is FormatException ? e.message : e}');
      return;
    }
    if (bytes == null) return;
    await save(bytes);
    if (context.mounted) tvNotice(context, poster ? 'New poster for "$name"' : 'New picture for "$name"');
  }

  final hints = pictureSearchHints(poster ? collection.category : video!.category);
  await showTvOptions(
    context,
    title: poster ? 'Poster for "$name"' : 'Picture for "$name"',
    subtitle: 'The new one shows on every page, instead of the automatic one',
    options: [
      if (online)
        TvOption('Search online', Icons.travel_explore, opensMore: true,
            subtitle: 'Posters and stills from TVmaze, AniList and Wikipedia', () {
          use(() => showTvPictureSearch(
                context,
                query: tvSearchName(poster ? collection.name : video!.collection),
                season: poster ? null : video!.season,
                episode: poster ? null : video!.episode,
                hint: hints.hint,
                anime: hints.anime,
                forPoster: poster,
              ));
        })
      else
        TvOption('Search online is off', Icons.travel_explore,
            subtitle: 'Settings › Online lookups › Find video pictures online', () {}),
      TvOption('Choose a picture file', Icons.folder_open, opensMore: true, subtitle: 'A picture on this TV or a USB drive', () {
        use(() async {
          final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture');
          final path = file?.path;
          if (path == null) return null;
          return preparePicture(await File(path).readAsBytes());
        });
      }),
      if (own)
        TvOption(poster ? 'Use the automatic poster' : 'Use the automatic picture', Icons.restore, () async {
          await save(null);
          if (context.mounted) tvNotice(context, poster ? 'Back to the automatic poster' : 'Back to the automatic picture');
        }),
    ],
  );
}

/// [name] tidied for searching: no release tags in brackets ("[Judas] Steins;Gate" → "Steins;Gate"),
/// dots and underscores as spaces ("Chainsaw.Man.The.Movie" → "Chainsaw Man The Movie"), and no
/// trailing "(TV Series)" or "1-26 DVD" bits. The search page lets the user type another.
String tvSearchName(String name) {
  var s = name.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  if (!s.contains(' ')) s = s.replaceAll(RegExp(r'[._]'), ' ');
  s = s.replaceAll(RegExp(r'\((?:TV[^)]*|\d{4}[^)]*)\)', caseSensitive: false), ' ');
  s = s.replaceAll(RegExp(r'\b\d+\s*-\s*\d+\b.*$'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.isEmpty ? name.trim() : s;
}

/// Opens the search page for [query]; returns the chosen picture (made a sensible size), or null.
Future<List<int>?> showTvPictureSearch(
  BuildContext context, {
  required String query,
  int? season,
  int? episode,
  String? hint,
  bool anime = false,
  bool forPoster = false,
  VideoArtSearch? search,
}) async {
  if (!await ensureOnline(context) || !context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<List<int>>(MaterialPageRoute(
    builder: (_) => TvPictureSearchPage(
        query: query, season: season, episode: episode, hint: hint, anime: anime, forPoster: forPoster, search: search),
  ));
}

/// The TV's picture search: what was searched for, "Search for another name", and the pictures
/// found as big tiles (posters first for a collection, wide pictures first for a video). OK on
/// one downloads it and closes the page; Back closes it with nothing chosen.
class TvPictureSearchPage extends StatefulWidget {
  const TvPictureSearchPage({
    super.key,
    required this.query,
    this.season,
    this.episode,
    this.hint,
    this.anime = false,
    this.forPoster = false,
    this.search,
  });
  final String query;
  final int? season, episode;
  final String? hint;
  final bool anime, forPoster;
  final VideoArtSearch? search;

  @override
  State<TvPictureSearchPage> createState() => _TvPictureSearchPageState();
}

class _TvPictureSearchPageState extends State<TvPictureSearchPage> {
  late final VideoArtSearch _search = widget.search ?? VideoArtSearch();
  late String _query = widget.query;
  VideoArtResults? _results;
  bool _busy = false;
  String? _downloading;
  String? _problem;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void dispose() {
    if (widget.search == null) _search.close();
    super.dispose();
  }

  Future<void> _find() async {
    final run = ++_run;
    setState(() {
      _busy = true;
      _problem = null;
    });
    // The typed name may not be the show's any more: only ask for the episode's still when unchanged.
    final same = _query == widget.query;
    final r = await _search.search(_query,
        season: same ? widget.season : null,
        episode: same ? widget.episode : null,
        wikipediaHint: widget.hint,
        order: widget.anime ? const ['AniList', 'TVmaze', 'Wikipedia'] : VideoArtSearch.services);
    if (!mounted || run != _run) return;
    setState(() {
      _results = r;
      _busy = false;
    });
  }

  Future<void> _another() async {
    final typed = await showTvTextInput(context, title: 'Search for', initial: _query, hint: 'The show or film\'s name');
    if (typed == null || typed.trim().isEmpty || !mounted) return;
    _query = typed.trim();
    await _find();
  }

  Future<void> _pick(VideoArtCandidate c) async {
    if (_downloading != null) return;
    setState(() {
      _downloading = c.fullUrl;
      _problem = null;
    });
    try {
      final picture = await preparePicture(await _search.download(c));
      if (mounted) Navigator.of(context).pop(picture);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = null;
          _problem = 'Couldn\'t get that picture: ${e is FormatException ? e.message : e}. Try another one.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    final found = r == null
        ? const <VideoArtCandidate>[]
        : [...r.found.where((c) => c.tall == widget.forPoster), ...r.found.where((c) => c.tall != widget.forPoster)];
    final status = _busy
        ? 'Searching for "$_query"…'
        : _downloading != null
            ? 'Getting that picture…'
            : r == null
                ? ''
                : '${found.length} picture${found.length == 1 ? '' : 's'} for "$_query"'
                    '${r.failed.isEmpty ? '' : ' · couldn\'t reach ${r.failed.join(' or ')} just now'}';
    // Over the whole screen (the app's own hint bubble is under it): its hints are its own.
    return Material(
      color: AppColors.bg,
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin + 16, TvStyle.topMargin, 28, TvStyle.bottomMargin),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(widget.forPoster ? 'Choose a poster' : 'Choose a picture',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
              ),
              TvButton(
                key: const ValueKey('tv-picture-search-again'),
                label: 'Search for another name',
                icon: Icons.search,
                onPressed: _busy ? null : _another,
              ),
            ]),
            const SizedBox(height: 6),
            Text(status, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_problem!, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : found.isEmpty
                      ? Center(
                          child: Text('Nothing found. Choose "Search for another name" to try a different name.',
                              style: TextStyle(fontSize: 15, color: AppColors.textDim)),
                        )
                      : TvAzGrid<VideoArtCandidate>(
                          key: ValueKey('tv-picture-results-$_query'),
                          items: found,
                          tileWidth: widget.forPoster ? 132 : 200,
                          aspectRatio: widget.forPoster ? 2 / 3 : 16 / 9,
                          itemBuilder: (context, c, i, node, w) => TvTile(
                            key: ValueKey('tv-picture-${c.fullUrl}'),
                            focusNode: node,
                            width: w,
                            aspectRatio: widget.forPoster ? 2 / 3 : 16 / 9,
                            title: '${c.kind} · ${c.source}',
                            subtitle: c.title,
                            onPressed: _downloading == null ? () => _pick(c) : null,
                            picture: Stack(fit: StackFit.expand, children: [
                              ColoredBox(color: AppColors.surface),
                              Image.network(
                                c.previewUrl,
                                fit: BoxFit.contain,
                                cacheWidth: 380,
                                headers: const {'User-Agent': VideoArtSearch.userAgent},
                                errorBuilder: (_, _, _) => Center(child: Icon(Icons.broken_image_outlined, color: AppColors.textDim)),
                              ),
                              if (_downloading == c.fullUrl)
                                const ColoredBox(color: Colors.black45, child: Center(child: CircularProgressIndicator())),
                            ]),
                          ),
                        ),
            ),
            Text(
              'Pictures from TVmaze (CC BY-SA), AniList and Wikipedia. Film posters on Wikipedia are usually '
              'copyrighted: fine for your own library, not for sharing.',
              style: TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ]),
        ),
        const Positioned(right: 24, bottom: 16, child: TvHints([('OK', 'Use this picture'), ('Back', 'Cancel')])),
      ]),
    );
  }
}
