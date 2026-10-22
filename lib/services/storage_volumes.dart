// The storage HomeTunes' own folder browser starts from (0.2.0): on Android, the device's own
// storage and any USB drive or SD card plugged in, from MainActivity's "storageVolumes"
// (Android's StorageManager). Google TV has no system folder picker, so "Add folder" there uses
// the app's own (ui/widgets/folder_browser.dart).
import 'dart:io';

import 'package:flutter/services.dart';

/// One place to start browsing from.
class StorageRoot {
  const StorageRoot(this.path, this.name, {this.removable = false});
  final String path;

  /// What Android calls it ("Internal shared storage", "SanDisk USB drive").
  final String name;

  /// A USB drive or SD card.
  final bool removable;
}

const _channel = MethodChannel('hometunes/app');

/// The storage to browse. Android only (elsewhere: none); the device's own if Android can't say.
Future<List<StorageRoot>> storageRoots() async {
  if (!Platform.isAndroid) return const [];
  try {
    final found = await _channel.invokeListMethod<Map<Object?, Object?>>('storageVolumes') ?? const [];
    final roots = [
      for (final v in found)
        if (v['path'] is String)
          StorageRoot(v['path']! as String, (v['name'] as String?) ?? 'Storage', removable: v['removable'] == true),
    ];
    if (roots.isNotEmpty) return roots;
  } catch (_) {}
  return const [StorageRoot('/storage/emulated/0', 'Internal storage')];
}
