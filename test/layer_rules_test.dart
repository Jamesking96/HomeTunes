// The layer rules (refactor phase 7, 9 Oct 2026), checked by reading every file's imports so they
// can't drift again. lib/ has four layers (docs/ai-context/05_CODE_GUIDE.md, "The big picture"):
//  * models/   plain data: imports no other layer and no Flutter library.
//  * state/    the app's live brain: never imports ui/, and from Flutter only the non-UI libraries
//              (foundation, scheduler, services).
//  * services/ files, network, the OS: never imports ui/; the few that reach into state/ are listed
//              below, so no new ones creep in.
//  * ui/       screens and widgets: may use read-only lookup services (cover search, MusicBrainz,
//              LRCLIB, Open Library, the update check…) but not the ones that write files or keep
//              the app's data (the user's rule, 8 Oct), and from the engine layer only the player
//              factory (engines.dart) and the video page's player (video_engine.dart): screens that
//              show a video make their player there (agreed in refactor phase 4).
// A broken rule fails with the file and the import, and what to do instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Every import / export in lib/, as (file, target): both relative to lib/ with '/', or the
/// package: / dart: address as written.
List<(String, String)> _imports() {
  final out = <(String, String)>[];
  final directive = RegExp(r"^\s*(?:import|export)\s+'([^']+)'", multiLine: true);
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final from = p.posix.joinAll(p.split(p.relative(f.path, from: 'lib')));
    for (final m in directive.allMatches(f.readAsStringSync())) {
      final uri = m.group(1)!;
      String target;
      if (uri.startsWith('package:hometunes/')) {
        target = uri.substring('package:hometunes/'.length);
      } else if (uri.startsWith('package:') || uri.startsWith('dart:')) {
        target = uri;
      } else {
        target = p.posix.normalize(p.posix.join(p.posix.dirname(from), uri));
      }
      out.add((from, target));
    }
  }
  return out;
}

String _layer(String path) => path.split('/').first;

/// Services that write files or keep the app's data: screens go through the models in state/.
const _writingServices = {
  'services/storage.dart',
  'services/tag_writer.dart',
  'services/app_backup.dart',
  'services/local_scanner.dart',
  'services/secret_store.dart',
  'services/server_art_cache.dart',
  'services/media_session.dart',
};

/// Screens allowed one of those, and why. Keep this short.
const _writingAllowed = {
  // Reads a chosen backup's summary (what's in it) before the user decides to restore; making
  // and restoring backups go through LibraryModel.
  ('ui/screens/settings/backup_settings.dart', 'services/app_backup.dart'),
};

/// Engine-layer files a screen may import.
const _engineForUi = {'services/engine/engines.dart', 'services/engine/video_engine.dart'};

/// Services that reach into state/ today (a service using a model's types or helpers). New ones
/// should pass what they need in instead.
const _servicesUsingState = {
  ('services/media_session.dart', 'state/library_model.dart'),
  ('services/media_session.dart', 'state/now_watching.dart'),
  ('services/media_session.dart', 'state/play_queue.dart'),
  ('services/media_session.dart', 'state/playback_guard.dart'),
  ('services/media_session.dart', 'state/player_model.dart'),
  ('services/path_safety.dart', 'state/book_index.dart'),
  ('services/server_probe.dart', 'state/servers_model.dart'),
};

/// Flutter libraries state/ may use (none of them draws anything).
const _flutterForState = {
  'package:flutter/foundation.dart',
  'package:flutter/scheduler.dart',
  'package:flutter/services.dart',
};

void main() {
  final imports = _imports();

  test('the import list is read (sanity check)', () {
    expect(imports.length, greaterThan(500));
    expect(imports, contains(('ui/shell.dart', 'package:flutter/material.dart')));
  });

  test('models/ imports no other layer and no Flutter library', () {
    final bad = [
      for (final (from, to) in imports)
        if (_layer(from) == 'models' &&
            (const {'state', 'services', 'ui'}.contains(_layer(to)) || to.startsWith('package:flutter/')))
          '$from imports $to',
    ];
    expect(bad, isEmpty, reason: 'Models are plain data (use dart:ui for a Color).');
  });

  test('state/ never imports ui/, and only the non-UI Flutter libraries', () {
    final bad = [
      for (final (from, to) in imports)
        if (_layer(from) == 'state' &&
            (_layer(to) == 'ui' || (to.startsWith('package:flutter/') && !_flutterForState.contains(to))))
          '$from imports $to',
    ];
    expect(bad, isEmpty, reason: 'State knows nothing about screens; move drawing code to ui/.');
  });

  test('services/ never imports ui/, and only the listed services reach into state/', () {
    final bad = [
      for (final (from, to) in imports)
        if (_layer(from) == 'services' &&
            (_layer(to) == 'ui' || (_layer(to) == 'state' && !_servicesUsingState.contains((from, to)))))
          '$from imports $to',
    ];
    expect(bad, isEmpty, reason: 'Pass what the service needs in, rather than importing a model.');
  });

  test('ui/ uses no file-writing or storage service, and only the player factory from the engine layer', () {
    final bad = [
      for (final (from, to) in imports)
        if (_layer(from) == 'ui' &&
            ((_writingServices.contains(to) && !_writingAllowed.contains((from, to))) ||
                (to.startsWith('services/engine/') && !_engineForUi.contains(to))))
          '$from imports $to',
    ];
    expect(bad, isEmpty, reason: 'Screens go through the models in state/ for anything that writes or plays.');
  });

  test('the listed exceptions are still needed (an unused one is taken off the list)', () {
    final all = imports.toSet();
    expect([for (final e in _writingAllowed) if (!all.contains(e)) e], isEmpty);
    expect([for (final e in _servicesUsingState) if (!all.contains(e)) e], isEmpty);
  });
}
