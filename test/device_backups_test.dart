// Backups kept on the device (14 Nov 2026): Android TV has no "save a file" or "open a file"
// screen, so on a TV a backup goes to HomeTunes' own folder and Import backup… lists them there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/device_backups.dart';
import 'package:path/path.dart' as p;

void main() {
  test('saved whole, then listed newest first (other files left out)', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_device_backups');
    addTearDown(() => dir.deleteSync(recursive: true));
    final old = await saveDeviceBackup(dir, 'HomeTunes-backup-2026-11-01.htbackup', [1, 2, 3]);
    old.setLastModifiedSync(DateTime(2026, 11, 1));
    final now = await saveDeviceBackup(dir, 'HomeTunes-backup-2026-11-14.htbackup', [4, 5]);
    File(p.join(dir.path, 'notes.txt')).writeAsStringSync('not a backup');
    expect(now.readAsBytesSync(), [4, 5]);
    expect(File('${now.path}.tmp').existsSync(), isFalse);
    expect([for (final f in deviceBackups(dir)) p.basename(f.path)],
        ['HomeTunes-backup-2026-11-14.htbackup', 'HomeTunes-backup-2026-11-01.htbackup']);
    expect(deviceBackups(Directory(p.join(dir.path, 'missing'))), isEmpty);
  });
}
