// Tests for 0.1.31's licences: the repository's MIT LICENSE, the bundled LGPL/GPL texts the audio
// engine needs, and the entries added to the app's licence page (Settings › About › Licences).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/app_licences.dart';

/// Serves the real files from the repository, like the app's asset bundle does.
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  test('the repository is MIT-licensed to Jamesking96', () {
    final text = File('LICENSE').readAsStringSync();
    expect(text, startsWith('MIT License'));
    expect(text, contains('Copyright (c) 2026 Jamesking96'));
    expect(text, contains('Permission is hereby granted, free of charge'));
    expect(licenceLegalese, contains('Jamesking96'));
  });

  test('the LGPL and GPL texts are the real ones and are bundled with the app', () {
    expect(File(lgplAsset).readAsStringSync(), contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(File(lgplAsset).readAsStringSync(), contains('Version 3, 29 June 2007'));
    expect(File(gplAsset).readAsStringSync(), contains('GNU GENERAL PUBLIC LICENSE'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- $lgplAsset'));
    expect(pubspec, contains('- $gplAsset'));
    expect(File('THIRD_PARTY_NOTICES.md').readAsStringSync(), contains('LGPL'));
  });

  test('the licence page gets the engine\'s notice, the LGPL, the GPL and its other libraries', () async {
    final entries = await audioEngineLicences(_FileBundle()).toList();
    expect(entries, hasLength(3));
    for (final e in entries.take(2)) {
      expect(e.packages, containsAll(['libmpv (mpv)', 'FFmpeg', 'libsoxr', 'GNU libiconv', 'uchardet']));
    }
    // 0.1.40: the video engine's other libraries, each with its licence text.
    expect(entries[2].packages, [engineComponentsName]);
    final components = entries[2].paragraphs.map((p) => p.text).join('\n');
    for (final name in ['libass', 'HarfBuzz', 'FreeType', 'dav1d', 'Mbed TLS', 'ANGLE', 'SwiftShader']) {
      expect(components, contains(name));
    }
    expect(components, contains('Permission is hereby granted')); // texts, not just names
    expect(File('pubspec.yaml').readAsStringSync(), contains('- $engineComponentsAsset'));
    String textOf(LicenseEntry e) => e.paragraphs.map((p) => p.text).join('\n');
    final first = textOf(entries[0]);
    expect(first, contains('Lesser General Public License, version 3 or later'));
    expect(first, contains('https://github.com/mpv-player/mpv'));
    expect(first, contains('HomeTunes-audio-engine-source.zip')); // where the source is
    expect(File('tool/engine_source.ps1').readAsStringSync(), contains('HomeTunes-audio-engine-source.zip'));
    expect(first, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(textOf(entries[1]), contains('GNU GENERAL PUBLIC LICENSE'));
  });

  test('if the texts are missing, the page still says where to read them', () async {
    final entries = await audioEngineLicences(_EmptyBundle()).toList();
    final all = entries.map((e) => e.paragraphs.map((p) => p.text).join('\n')).join('\n');
    expect(all, contains('https://www.gnu.org/licenses/lgpl-3.0.txt'));
    expect(all, contains('https://www.gnu.org/licenses/gpl-3.0.txt'));
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('missing $key'));
}
