// Pictures for songs, books and artists, as Flutter images (refactor phase 3, 8 Oct 2026).
// LibraryModel says where a cover comes from (a file on disk or the server's address, see
// LibraryModel.coverSource); this turns that into something Flutter can draw, so the state
// folder doesn't need Flutter's image classes. The names are the ones LibraryModel used to have,
// so `lib.artFor(track)` reads as before wherever this file is imported.
import 'dart:io';

import 'package:flutter/painting.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';

extension LibraryImages on LibraryModel {
  /// The cover image to show in the app: a file on disk, or the server's cover picture.
  ImageProvider? artFor(Track? t, {int size = 512}) => _image(coverSource(t, size: size));

  /// The picture to draw for an artist: their own file, the chosen album cover, or the first
  /// album's cover.
  ImageProvider? artistImage(Artist a, {int size = 512}) => _image(artistSource(a, size: size));
}

ImageProvider? _image(PictureSource? s) => switch (s) {
      null => null,
      (file: final String file, url: _) => FileImage(File(file)),
      (file: null, url: final String url) => NetworkImage(url),
      _ => null,
    };
